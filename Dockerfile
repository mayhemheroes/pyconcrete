FROM --platform=linux/amd64 ubuntu:20.04

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y python python-dev build-essential

ADD . /repo
WORKDIR /repo
RUN python setup.py install < stdin
