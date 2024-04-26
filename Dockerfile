FROM registry.access.redhat.com/ubi9/ubi:latest

MAINTAINER Anthony Green <green@moxielogic.com>

ENV LC_ALL=C.utf8 \
    LANG=C.utf8 \
    LANGUAGE=C.utf8 \
    SBCL_VERSION=2.3.4

ENV HOME=/home/ocicl-manage
ENV PATH=${HOME}/bin:${HOME}/.local/bin:$PATH

RUN dnf -y update && dnf -y install git bzip2 make

RUN groupadd -r -g 1001 ocicl-manage && \
    useradd -r -u 1001 -g ocicl-manage -m -d ${HOME} -s /bin/bash ocicl-manage && \
    chmod go+rwx ${HOME}

COPY manage.lisp /home/ocicl-manage/manage.lisp
RUN chown -R ocicl-manage /home/ocicl-manage

USER 1001

WORKDIR /home/ocicl-manage

RUN curl -L -O "https://downloads.sourceforge.net/project/sbcl/sbcl/${SBCL_VERSION}/sbcl-${SBCL_VERSION}-x86-64-linux-binary.tar.bz2" \
    && tar -xf sbcl-${SBCL_VERSION}-x86-64-linux-binary.tar.bz2 \
    && cd sbcl-${SBCL_VERSION}-x86-64-linux \
    && ./install.sh --prefix=${HOME} \
    && cd .. \
    && rm -rf sbcl-${SBCL_VERSION}-x86-64-linux-binary.tar.bz2 sbcl-${SBCL_VERSION}-x86-64-linux

RUN git config --global user.email "green@moxielogic.com" && \
    git config --global user.name "Anthony Green"

RUN git clone --depth=1 https://github.com/ocicl/ocicl.git && \
    cd ocicl && \
    make && \
    make install && \
    ocicl version && \
    ocicl setup > ~/.sbclrc

RUN ocicl install cl-github-v3 legit cl-ppcre split-sequence privacy-output-stream

RUN curl -L -O "https://github.com/atgreen/green-orb/releases/download/v0.2.1/green-orb-0.2.1-linux-amd64.tar.gz" \
    && tar xf green-orb-0.2.1-linux-amd64.tar.gz \
    && rm green-orb-0.2.1-linux-amd64.tar.gz \
    && echo "# Replace this file to enable the orb" > green-orb.yaml

RUN mkdir repos
USER 0
RUN chmod -R 777 ${HOME}
USER 1001

CMD ./orb sbcl --load manage.lisp
