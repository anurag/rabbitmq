FROM rabbitmq:3.7.18-management

ARG RABBITMQ_NODENAME
ENV RABBITMQ_NODENAME=$RABBITMQ_NODENAME

COPY rabbitmq.conf /etc/rabbitmq/

RUN chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf
