FROM rabbitmq:3.7.18-management

COPY rabbitmq.conf rabbitmq-env.conf /etc/rabbitmq/

COPY start.sh .

RUN chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf

ENTRYPOINT []

CMD ["./start.sh"]
