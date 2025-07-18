FROM ubuntu:24.04

RUN apt-get update && apt-get install -y freeradius-utils curl && rm -rf /var/lib/apt/lists/*

COPY ./test /usr/local/bin/test
RUN chmod +x /usr/local/bin/test

CMD ["tail", "-f", "/dev/null"]