FROM rabbitmq:3.7.18-management

COPY rabbitmq.conf rabbitmq-env.conf /etc/rabbitmq/

RUN chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf

USER rabbitmq:rabbitmq
