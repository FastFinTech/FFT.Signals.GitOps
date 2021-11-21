FROM amazon/aws-cli:2.0.43

# install handy commandline tools
RUN yum install -y jq gzip nano tar git unzip wget

# install terraform and kubectl
RUN curl -o /tmp/terraform.zip -LO https://releases.hashicorp.com/terraform/1.0.11/terraform_1.0.11_linux_amd64.zip \
    && unzip /tmp/terraform.zip \
    && chmod +x terraform \
    && mv terraform /usr/local/bin/ \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl

