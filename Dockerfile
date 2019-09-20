FROM rabbitmq:3.7.18-management

ENV RABBITMQ_USE_LONGNAME=true

COPY rabbitmq.conf rabbitmq-env.conf /etc/rabbitmq/

RUN chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf

USER rabbitmq:rabbitmq
