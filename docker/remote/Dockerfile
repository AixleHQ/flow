FROM amazon/aws-cli:2.27.16

ARG platform

RUN curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/$platform/session-manager-plugin.rpm" -o "/tmp/session-manager-plugin.rpm"
RUN amazon-linux-extras install ruby3.0
RUN yum install -y jq gcc redhat-rpm-config which make ruby-devel pip /tmp/session-manager-plugin.rpm
RUN pip install awslogs
RUN curl -Ls https://raw.githubusercontent.com/aws-containers/amazon-ecs-exec-checker/main/check-ecs-exec.sh > /usr/local/bin/check-ecs-exec && chmod +x /usr/local/bin/check-ecs-exec
RUN gem install ecs_helper

RUN mkdir /app
WORKDIR /app

ENTRYPOINT ["/bin/bash", "-c"]
