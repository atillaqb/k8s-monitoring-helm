#!/bin/bash

set -eo pipefail

AGENT_HOST="${AGENT_HOST:-http://localhost:8080}"

function discoveryKubernetes() {
    local details=$1
    jq -r '"  Found: (\(.exports[0].value.value | length))"' <(echo "${details}")
}

function discoveryRelabel() {
    local details=$1
    jq -r '"  Inputs: \(.referencesTo[0]) (\(.arguments[0].value.value | length))"' <(echo "${details}")
    jq -r '"  Outputs: \(.referencedBy[0]) (\(.exports[0].value.value | length))"' <(echo "${details}")
}

function prometheusScrape() {
    local details=$1
    inputCount=$(jq -r '.arguments[] | select(.name == "targets") | .value.value | length' <(echo "${details}"))
    echo "  Inputs: ${inputCount}"
    if [ "${inputCount}" -gt 0 ]; then
        for i in $(seq 1 "${inputCount}"); do
            jq -r --argjson i "${i}" '"  - \(.arguments[] | select(.name == "targets") | .value.value[$i-1].value[] | select(.key == "__address__") | .value.value)"' <(echo "${details}")
        done
    fi

    targetCount=$(jq -r '.debugInfo | length' <(echo "${details}"))
    echo "  Scrapes: ${targetCount}"
    if [ "${targetCount}" -gt 0 ]; then
        for i in $(seq 1 "${targetCount}"); do
            jq -r --argjson i "${i}" '"  - URL: \(.debugInfo[$i-1].body[] | select(.name == "url") | .value.value)"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Health: \(.debugInfo[$i-1].body[] | select(.name == "health") | .value.value)"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Last scrape: \(.debugInfo[$i-1].body[] | select(.name == "last_scrape") | .value.value) (\(.debugInfo[0].body[] | select(.name == "last_scrape_duration") | .value.value))"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Scrape error: \(.debugInfo[$i-1].body[] | select(.name == "last_error") | .value.value)"' <(echo "${details}")
        done
    fi
}

function prometheusOperatorMetricObject() {
    local details=$1
    inputs=$(jq -r '[.debugInfo[] | select(.name == "crds")]' <(echo "${details}"))
    inputCount=$(jq length <(echo "${inputs}"))
    echo "  Discovered: ${inputCount}"
    if [ "${inputCount}" -gt 0 ]; then
        for i in $(seq 1 "${inputCount}"); do
            name=$(jq -r --argjson i "${i}" '.[$i-1].body[] | select(.name == "name") | .value.value' <(echo "${inputs}"))
            namespace=$(jq -r --argjson i "${i}" '.[$i-1].body[] | select(.name == "namespace") | .value.value' <(echo "${inputs}"))
            echo "  - ServiceMonitor: ${namespace}/${name}"
        done
    fi

    scrapes=$(jq -r '[.debugInfo[] | select(.name == "targets")]' <(echo "${details}"))
    scrapeCount=$(jq length <(echo "${scrapes}"))
    echo "  Scrapes: ${scrapeCount}"
    if [ "${scrapeCount}" -gt 0 ]; then
        for i in $(seq 1 "${scrapeCount}"); do
            jq -r --argjson i "${i}" '"  - URL: \(.[$i-1].body[] | select(.name == "url") | .value.value)"' <(echo "${scrapes}")
            jq -r --argjson i "${i}" '"    Health: \(.[$i-1].body[] | select(.name == "health") | .value.value)"' <(echo "${scrapes}")
            jq -r --argjson i "${i}" '"    Last scrape: \(.[$i-1].body[] | select(.name == "last_scrape") | .value.value) (\(.[0].body[] | select(.name == "last_scrape_duration") | .value.value))"' <(echo "${scrapes}")
            jq -r --argjson i "${i}" '"    Scrape error: \(.[$i-1].body[] | select(.name == "last_error") | .value.value)"' <(echo "${scrapes}")
        done
    fi
}

if [ -z "${AGENT_HOST}" ]; then
    echo "AGENT_HOST is not defined. Please set AGENT_HOST to the Grafana Agent host."
    exit 1
fi

if ! curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components" > /dev/null; then
    echo "Failed to send a request to the Agent. Check that AGENT_HOST is set correctly."
    exit 1
fi

components=$(curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components" | jq -r '.[].localID' | sort)
while IFS= read -r component; do
    details=$(curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components/${component}")
    case "${component}" in
      discovery.kubernetes.*)
        echo "${component}"
        discoveryKubernetes "${details}"
        echo
        ;;
      discovery.relabel.*)
        echo "${component}"
        discoveryRelabel "${details}"
        echo
        ;;
      prometheus.scrape.*)
        echo "${component}"
        prometheusScrape "${details}"
        echo
        ;;
      prometheus.operator.podmonitors.*)
        echo "${component}"
        prometheusOperatorMetricObject "${details}"
        echo
        ;;
      prometheus.operator.servicemonitors.*)
        echo "${component}"
        prometheusOperatorMetricObject "${details}"
        echo
        ;;
    esac
done <<< "${components}"
