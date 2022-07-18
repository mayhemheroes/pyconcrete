FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y python python-dev build-essential

ADD . /repo
WORKDIR /repo
RUN python setup.py install < stdin

RUN mkdir -p /deps
RUN ldd @#% | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder @#% @#%
ENV LD_LIBRARY_PATH=/deps
