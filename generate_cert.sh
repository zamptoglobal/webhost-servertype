#!/bin/bash

# Constants for certificate paths
CERT_DIR="/home/container/ssl"
KEY_FILE="${CERT_DIR}/server.key"
CERT_FILE="${CERT_DIR}/server.crt"
CSR_FILE="${CERT_DIR}/server.csr"
CERT_INFO_FILE="${CERT_DIR}/cert_info.json"

# Function: convert duration to days
get_days_from_duration() {
    if [ "$1" = "3months" ]; then
        echo "90"
    elif [ "$1" = "6months" ]; then
        echo "180"
    elif [ "$1" = "12months" ]; then
        echo "365"
    elif [ "$1" = "2years" ]; then
        echo "730"
    elif [ "$1" = "5years" ]; then
        echo "1825"
    elif [ "$1" = "10years" ]; then
        echo "3650"
    else
        echo "365"
    fi
}

needs_renewal() {
    local renewal_policy="$1"

    # If no cert exists, needs renewal
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "No certificate found - needs generation" >&2
        return 0
    fi

    # Get expiry date and convert to seconds
    local exp_date
    exp_date=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
    local exp_seconds
    exp_seconds=$(date -d "$exp_date" +%s)
    local now_seconds
    now_seconds=$(date +%s)
    local days_until_expiry=$(( (exp_seconds - now_seconds) / 86400 ))

    echo "Certificate expires in $days_until_expiry days" >&2
    
    case "$renewal_policy" in
        "boot")
            echo "Boot policy - always renewing" >&2
            return 0
            ;;
        "1day")
            if [ $days_until_expiry -le 1 ]; then 
                echo "Less than 1 day until expiry - renewing" >&2
                return 0
            fi
            ;;
        "2days")
            if [ $days_until_expiry -le 2 ]; then
                echo "Less than 2 days until expiry - renewing" >&2
                return 0
            fi
            ;;
        "14days")
            if [ $days_until_expiry -le 14 ]; then
                echo "Less than 14 days until expiry - renewing" >&2
                return 0
            fi
            ;;
        "1month")
            if [ $days_until_expiry -le 30 ]; then
                echo "Less than 30 days until expiry - renewing" >&2
                return 0
            fi
            ;;
        *)
            if [ $days_until_expiry -le 2 ]; then
                echo "Using default 2-day policy - renewing" >&2
                return 0
            fi
            ;;
    esac

    echo "No renewal needed based on policy $renewal_policy" >&2
    return 1
}

generate_certificate() {
    local duration="$1"
    local server_ip="$2"
    local server_port="$3"

    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    echo "Generating SSL certificate for $server_ip:$server_port (valid for $duration)"

    local days
    days=$(get_days_from_duration "$duration")
    local cn="${SERVER_FQDN:-$server_ip}"

    if ! openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$KEY_FILE" \
        -out "$CSR_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${cn}" 2>/dev/null; then
        echo "Error: Failed to generate private key and CSR"
        return 1
    fi

    if ! openssl x509 -req -days "$days" \
        -in "$CSR_FILE" \
        -signkey "$KEY_FILE" \
        -out "$CERT_FILE" 2>/dev/null; then
        echo "Error: Failed to generate self-signed certificate"
        return 1
    fi

    echo "{
        \"generated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
        \"expires_at\": \"$(date -u -d "+${days} days" +"%Y-%m-%dT%H:%M:%SZ")\",
        \"server_ip\": \"${server_ip}\",
        \"server_port\": \"${server_port}\"
    }" > "$CERT_INFO_FILE"

    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    chmod 644 "$CERT_INFO_FILE"

    rm -f "$CSR_FILE"
}

if [ "$1" = "check" ]; then
    needs_renewal "$2"
    exit $?
elif [ "$1" = "generate" ]; then
    generate_certificate "$2" "$3" "$4"
fi
