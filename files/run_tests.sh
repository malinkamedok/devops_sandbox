#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

debug() {
    echo -e "${YELLOW}[DEBUG] $1${NC}"
}

info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

mkdir -p results/{weather,currency}

TESTCASES_DIR="/testcases"
PYTHON_FILE=`find . -name "main.py" -type f`
GO_FILE=`find . -name "main.go" -type f`
MAIN_FILE=""
COMMAND=""

if [ -z "$PYTHON_FILE" ] && [ -z "$GO_FILE" ]; then
    error "Both PYTHON_FILE and GO_FILE are empty. Exiting the program."
    exit 1
fi

if [ -n "$PYTHON_FILE" ] && [ -f "$PYTHON_FILE" ]; then
    debug "Found Python application..."
    MAIN_FILE="$PYTHON_FILE"
    # Check if requirements.txt exists in the current directory
    if [ -f requirements.txt ]; then
        debug "requirements.txt found. Installing dependencies with pip..."
        pip install -r requirements.txt
    fi
    # Check if pyproject.toml exists in the current directory
    if [ -f pyproject.toml ]; then
        debug "pyproject.toml found. Installing dependencies with Poetry..."
        if ! command -v poetry &> /dev/null; then
            error "Poetry not found. Exiting..."
        fi
        poetry install
    else
        error "Neither requirements.txt nor pyproject.toml found. Skipping installation."
        exit 1
    fi
    COMMAND=""
fi

if [ -n "$GO_FILE" ] && [ -f "$GO_FILE" ]; then
    debug "Found Go application..."
    go mod tidy
    if [ $? -ne 0 ]; then
        error "Could not install Go dependencies"
        exit 1
    fi
    info "Project dependencies installed..."

    go build -o student_app $GO_FILE
    if [ $? -ne 0 ]; then
        error "Could not build Go application"
        exit 1
    fi
    info "App built successfully..."
    MAIN_FILE=`realpath ./student_app`
    COMMAND="$MAIN_FILE"
fi

export PORT=$(shuf -i 8181-9191 -n 1)

debug "Allocating port $PORT"

# nohup let's us quit process's terminal without stopping it
nohup $COMMAND &
sleep 2

info "Figuring out which service type..."

curl -X GET http://localhost:$PORT/info/ -o results/info.json >/dev/null 2>/dev/null

SERVICE_TYPE=`jq -r '.service' results/info.json`

if [ -z "$SERVICE_TYPE" ]; then
    error "No service type provided"
    exit 1
fi

debug "SERVICE_TYPE=$SERVICE_TYPE"


info "Generating test cases"

# TODO

info "Running tests..."


# for i in {1..10}
for i in {1..4}
do
    PARAMS=`cat $TESTCASES_DIR/$SERVICE_TYPE/$i.params`
    # curl -X GET https://devopscourseapp-production.up.railway.app/info/$SERVICE_TYPE?$PARAMS -o results/$SERVICE_TYPE/response_$i.json >/dev/null 2>/dev/null
    curl -X GET http://localhost:$PORT/info/$SERVICE_TYPE?$PARAMS -o results/$SERVICE_TYPE/response_$i.json >/dev/null 2>/dev/null
    echo "URL:        http://localhost:$PORT/info/$SERVICE_TYPE?$PARAMS"
    echo "Parameters: $PARAMS"
    echo "Output:"
    jq . results/$SERVICE_TYPE/response_$i.json

    python $TESTCASES_DIR/compare_results.py $TESTCASES_DIR/$SERVICE_TYPE/answer_$i.json results/$SERVICE_TYPE/response_$i.json

    if [ $? -ne 0 ]; then
        error "TEST $i FAILED"
        debug "Stopping server"
        kill $(pgrep -f `realpath "$MAIN_FILE"`)
        exit 1
    fi
    info "TEST $i PASSED"
done

debug "Stopping server"

kill $(pgrep -f `realpath "$MAIN_FILE"`)
