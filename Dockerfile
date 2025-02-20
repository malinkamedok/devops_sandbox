FROM ubuntu:23.10@sha256:50ec5c3a1814f5ef82a564fae94f6b4c5d550bb71614ba6cfe8fadbd8ada9f12
ARG GO_VERSION=go1.22.1
ARG PYTHON_VERSION=3.12
RUN apt-get update -y -q && apt-get upgrade -y -q

ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV TZ Europe/Moscow

RUN apt-get install --no-install-recommends -y -q \
    curl=8.2.1-1ubuntu3.3 \
    build-essential=12.10ubuntu1 \
    ca-certificates=20230311ubuntu1 \
    git=1:2.40.1-1ubuntu1 \
    make=4.3-4.1build1 \
    gcc=4:13.2.0-1ubuntu1 \
    g++=4:13.2.0-1ubuntu1 \
    gnupg=2.2.40-1.1ubuntu1 \
    unixodbc-dev=2.3.12-1ubuntu0.23.10.1 \
    jq=1.6-3 \
    bc=1.07.1-3build1 \
    xmlstarlet=1.6.1-3

# Install Go
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -s https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH $PATH:/usr/local/go/bin


## Install Python
RUN apt-get install --no-install-recommends -y -q \
  python${PYTHON_VERSION}-full=3.12.0-1 \
  python3-pip=23.2+dfsg-1ubuntu0.1 \
  python3-poetry=1.6.1+dfsg-2  \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 2 && poetry config virtualenvs.create false

RUN rm -f /usr/bin/python3 && ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python3

COPY files/run_tests.sh /usr/bin/run_tests
RUN chmod +x /usr/bin/run_tests

COPY files/testcases /testcases
