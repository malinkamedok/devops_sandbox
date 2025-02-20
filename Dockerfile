FROM ubuntu:24.04
ARG GO_VERSION=go1.22.1
ARG PYTHON_VERSION=3.12
RUN apt-get update -y -q && apt-get upgrade -y -q

ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV TZ Europe/Moscow

RUN apt-get install --no-install-recommends -y -q \
    curl \
    build-essential \
    ca-certificates \
    git \
    make \
    gcc \
    g++= \
    gnupg \
    unixodbc-dev \
    jq \
    bc \
    xmlstarlet

# Install Go
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -s https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH $PATH:/usr/local/go/bin


## Install Python
RUN apt-get install --no-install-recommends -y -q \
  python${PYTHON_VERSION}-full \
  python3-pip \
  python3-poetry  \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 2 && poetry config virtualenvs.create false

RUN rm -f /usr/bin/python3 && ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python3

COPY files/run_tests.sh /usr/bin/run_tests
RUN chmod +x /usr/bin/run_tests

COPY files/testcases /testcases
