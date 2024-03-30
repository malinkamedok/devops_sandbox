FROM ubuntu:23.10@sha256:50ec5c3a1814f5ef82a564fae94f6b4c5d550bb71614ba6cfe8fadbd8ada9f12
ARG GO_VERSION=go1.22.1
ARG PYTHON_VERSION=3.12
RUN apt update -y -q && apt upgrade -y -q

ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

RUN apt install --no-install-recommends -y -q \
    curl \
    build-essential \
    ca-certificates \
    git \
    make \
    gcc \
    g++ \
    gnupg \
    unixodbc-dev \
    jq \
    bc \
    xmlstarlet

# Install Go
RUN curl -s https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH $PATH:/usr/local/go/bin


## Install Python
RUN apt install --no-install-recommends -y -q \
  python${PYTHON_VERSION}-full \
  python3-pip \
  python3-poetry

RUN update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 2
RUN poetry config virtualenvs.create false

ADD files/run_tests.sh /usr/bin/run_tests
RUN chmod +x /usr/bin/run_tests

ADD files/testcases /testcases
