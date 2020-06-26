FROM ubuntu:20.04
    MAINTAINER Daniel Salfran <danielsalfran@gmail.com>

USER root

#### BASICS ####
# Environemt variables
ENV \
    SHELL="/bin/bash" \
    HOME="/root"  \
    NB_USER="root" \
    USER_GID=0 \
    XDG_CACHE_HOME="/root/.cache/" \
    XDG_RUNTIME_DIR="/tmp" \
    RESOURCES_PATH="/resources" \
    WORKSPACE_HOME="/workspace" \
    LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    DEBIAN_FRONTEND="noninteractive"


# Configure workspace
RUN mkdir $WORKSPACE_HOME && chmod a+rwx $WORKSPACE_HOME && \
    mkdir $RESOURCES_PATH && chmod a+rwx $RESOURCES_PATH

WORKDIR $HOME

COPY resources/scripts/clean-layer.sh  /usr/bin/clean-layer.sh
COPY resources/scripts/fix-permissions.sh  /usr/bin/fix-permissions.sh

RUN apt-get update && apt-get upgrade -y && \
    # Install basics
    apt-get install -y --no-install-recommends \
    locales \
    sudo apt-utils nano less lsb-release jq\
    # Certificates, and dependencies
    dirmngr ca-certificates ca-certificates-java apt-transport-https \
    # Install downloaders
    curl wget \
    # Compilers and libraries
    build-essential \
    # Numerical libraries
    libopenblas-base liblapack-dev libatlas-base-dev libeigen3-dev libblas-dev \
    # Python 3.8
    python3 python3-dev python3-distutils python3-pip\
    # Java 8
    openjdk-11-jdk \
    # git
    git \
    # Install compression libraries
    zip gzip unzip bzip2 lzop libarchive-tools zlibc \
    # Image and video processing
    ffmpeg dvipng && \
    # Configure locale
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8 && \
    # Configure python 3
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    update-alternatives --set python /usr/bin/python3 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 && \
    update-alternatives --set pip /usr/bin/pip3 && \
    # Install Node JS
    curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y nodejs && \
    # Make utility scripts executable
    chmod a+rwx /usr/bin/clean-layer.sh && \
    chmod a+rwx /usr/bin/fix-permissions.sh && \
    # Cleanup
    clean-layer.sh

#### END BASICS ####

#### PROCESSES ####
 
## SSH
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        # SSLH for SSH + HTTP(s) Multiplexing
        sslh \
        # SSH Tooling
        autossh \
        mussh && \
    chmod go-w $HOME && \
    mkdir -p $HOME/.ssh/ && \
    # create empty config file if not exists
    touch $HOME/.ssh/config  && \
    sudo chown -R $NB_USER:users $HOME/.ssh && \
    chmod 700 $HOME/.ssh && \
    printenv >> $HOME/.ssh/environment && \
    chmod -R a+rwx /usr/local/bin/ && \
    # Fix permissions
    fix-permissions.sh $HOME && \
    # Cleanup
    clean-layer.sh

## NGINX
RUN \
    OPEN_RESTY_VERSION="1.15.8.3" && \
    mkdir $RESOURCES_PATH"/openresty" && \
    cd $RESOURCES_PATH"/openresty" && \
    apt-get update && \
    apt-get purge -y nginx nginx-common && \
    # libpcre required, otherwise you get a 'the HTTP rewrite module requires the PCRE library' error
    # Install apache2-utils to generate user:password file for nginx.
    apt-get install -y libssl-dev libpcre3 libpcre3-dev apache2-utils && \
    wget --quiet https://openresty.org/download/openresty-$OPEN_RESTY_VERSION.tar.gz  -O ./openresty.tar.gz && \
    tar xfz ./openresty.tar.gz && \
    rm ./openresty.tar.gz && \
    cd ./openresty-$OPEN_RESTY_VERSION/ && \
    # Surpress output - if there is a problem remove  > /dev/null
    ./configure --with-http_stub_status_module --with-http_sub_module > /dev/null && \
    make -j2 > /dev/null && \
    make install > /dev/null && \
    # create log dir and file - otherwise openresty will throw an error
    mkdir -p /var/log/nginx/ && \
    touch /var/log/nginx/upstream.log && \
    cd $RESOURCES_PATH && \
    rm -r $RESOURCES_PATH"/openresty" && \
    # Fix permissions
    chmod -R a+rwx $RESOURCES_PATH && \
    # Cleanup
    clean-layer.sh

# Install supervisor for process supervision
RUN \
    apt-get update && \
    # Create sshd run directory - required for starting process via supervisor
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
    # Install rsyslog for syslog logging
    apt-get install -y --no-install-recommends rsyslog && \
    pip install --no-cache-dir --upgrade supervisor supervisor-stdout && \
    # supervisor needs this logging path
    mkdir -p /var/log/supervisor/ && \
    # Cleanup
    clean-layer.sh

#### END PROCESSES ####

#### APACHE SPARK
ENV \
    APACHE_SPARK_VERSION=3.0.0 \
    HADOOP_VERSION=3.2

RUN cd /tmp && \
    wget -q $(wget -qO- https://www.apache.org/dyn/closer.lua/spark/spark-${APACHE_SPARK_VERSION}/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz\?as_json | \
    python -c "import sys, json; content=json.load(sys.stdin); print(content['preferred']+content['path_info'])") && \
    echo "3c9bef2d002d706b5331415884d3f890ecfdd7c6a692f36ed7a981ad120b2482 *spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" | sha512sum -c - && \
    tar xzf spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz -C /usr/local --owner root --group root --no-same-owner && \
    rm spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz && \
    cd /usr/local && ln -s spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} spark

ENV \
    SPARK_HOME=/usr/local/spark \
    PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.8.1-src.zip \
    SPARK_OPTS="--driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M --driver-java-options=-Dlog4j.logLevel=info" \
    PATH=$PATH:$SPARK_HOME/bin

#### PYTHON ####
COPY resources/libraries/requirements.txt ${RESOURCES_PATH}/libraries/

# Install Tensorflow Numpy and Sklearn
RUN pip --no-cache-dir install -r ${RESOURCES_PATH}/libraries/requirements.txt

COPY resources/libraries/ ${RESOURCES_PATH}/libraries/
# Install standard ML and development libraries
RUN pip --no-cache-dir install -r ${RESOURCES_PATH}/libraries/requirements-extra.txt && \
    python -m spacy download en && \
    python -m spacy download de && \
    python -m spacy download es

# Install Jupyter libraries
RUN pip --no-cache-dir install -r ${RESOURCES_PATH}/libraries/requirements-jupyter.txt

#### END PYTHON ####

#### JUPYTER ####

COPY \
    resources/jupyter/start.sh \
    resources/jupyter/start-notebook.sh \
    resources/jupyter/start-singleuser.sh \
    /usr/local/bin/

# install jupyter extensions
RUN \
    # Activate and configure extensions
    jupyter contrib nbextension install --user && \
    # nbextensions configurator
    jupyter nbextensions_configurator enable --user && \
    # Active nbresuse
    jupyter serverextension enable --py nbresuse && \
    # Activate Jupytext
    jupyter nbextension enable --py jupytext && \
    # Disable Jupyter Server Proxy
    jupyter nbextension disable jupyter_server_proxy/tree && \
    # Enable useful extensions
    jupyter nbextension enable skip-traceback/main && \
    # jupyter nbextension enable comment-uncomment/main && \
    # Do not enable variable inspector: causes trouble: https://github.com/ml-tooling/ml-workspace/issues/10
    # jupyter nbextension enable varInspector/main && \
    #jupyter nbextension enable spellchecker/main && \
    jupyter nbextension enable toc2/main && \
    jupyter nbextension enable execute_time/ExecuteTime && \
    jupyter nbextension enable collapsible_headings/main && \
    jupyter nbextension enable codefolding/main && \
    echo '{"nbext_hide_incompat": false}' > $HOME/.jupyter/nbconfig/common.json && \
    cat $HOME/.jupyter/nbconfig/notebook.json | jq '.toc2={"moveMenuLeft": false,"widenNotebook": false,"skip_h1_title": false,"sideBar": true,"number_sections": false,"collapse_to_match_collapsible_headings": true}' > tmp.$$.json && mv tmp.$$.json $HOME/.jupyter/nbconfig/notebook.json && \
    # Activate qgrid
    jupyter nbextension enable --py --sys-prefix qgrid

# install jupyterlab
RUN \
    jupyter labextension install @jupyter-widgets/jupyterlab-manager && \
    jupyter labextension install @jupyterlab/toc && \
    jupyter labextension install jupyterlab_tensorboard && \
    # install jupyterlab git
    jupyter labextension install @jupyterlab/git && \
    pip install jupyterlab-git && \ 
    jupyter serverextension enable --py jupyterlab_git && \
    # For Matplotlib: https://github.com/matplotlib/jupyter-matplotlib
    jupyter labextension install jupyter-matplotlib && \
    # Install jupyterlab language server support
    pip install --pre jupyter-lsp && \
    jupyter labextension install @krassowski/jupyterlab-lsp && \
    # For holoview
    jupyter labextension install @pyviz/jupyterlab_pyviz && \
    # Install jupyterlab variable inspector - https://github.com/lckr/jupyterlab-variableInspector
    jupyter labextension install @lckr/jupyterlab_variableinspector && \
    # Install jupyterlab code formattor - https://github.com/ryantam626/jupyterlab_code_formatter
    jupyter labextension install @ryantam626/jupyterlab_code_formatter && \
    pip install jupyterlab_code_formatter && \
    jupyter serverextension enable --py jupyterlab_code_formatter && \
    # Cleanup
    # Clean jupyter lab cache: https://github.com/jupyterlab/jupyterlab/issues/4930
    jupyter lab clean && \
    jlpm cache clean && \
    # Remove build folder -> should be remove by lab clean as well?0
    clean-layer.sh

# Install Jupyter Tooling Extension
COPY resources/jupyter/extensions $RESOURCES_PATH/jupyter-extensions

RUN pip install --no-cache-dir $RESOURCES_PATH/jupyter-extensions/tooling-extension/ && \
    # Cleanup
    clean-layer.sh

# Copy jupyter system configuration
COPY resources/jupyter/nbconfig /etc/jupyter/nbconfig
COPY resources/jupyter/jupyter_notebook_config.py resources/jupyter/jupyter_notebook_config.json resources/jupyter/nbconfig /etc/jupyter/
COPY resources/jupyter/sidebar.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/application-extension/
COPY resources/jupyter/plugin.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/extensionmanager-extension/
COPY resources/jupyter/ipython_config.py /etc/ipython/ipython_config.py

# Download and install tini kernel
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

#### END JUPYTER ####

#### CONFIGURATION ####

# Copy basic jupyter / pyspark tutorials
COPY resources/tutorials $RESOURCES_PATH/tutorials

# Configure ssh
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/
RUN touch $HOME/.ssh/config

# Confiture nginx
COPY resources/nginx/nginx.conf /etc/nginx/nginx.conf
COPY resources/nginx/lua-extensions /etc/nginx/nginx_plugins
ENV PATH=/usr/local/openresty/nginx/sbin:$PATH

# Configure supervisor process
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# Copy all supervisor program definitions into workspace
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Copy scripts into workspace
COPY resources/scripts $RESOURCES_PATH/scripts

RUN chmod -R a+rwx $WORKSPACE_HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    chmod -R a+rwx /usr/share/applications/ && \
    chmod a+rwx /usr/local/bin/start-notebook.sh && \
    chmod a+rwx /usr/local/bin/start.sh && \
    chmod a+rwx /usr/local/bin/start-singleuser.sh && \
    chmod a+rwx /tmp && \
    echo  'cd '$WORKSPACE_HOME >> $HOME/.bashrc

COPY \
    resources/docker-entrypoint.py \
    resources/5xx.html \
    $RESOURCES_PATH/

# Set default values for environment variables
ENV CONFIG_BACKUP_ENABLED="true" \
    SHUTDOWN_INACTIVE_KERNELS="false" \
    SHARED_LINKS_ENABLED="true" \
    AUTHENTICATE_VIA_JUPYTER="false" \
    DATA_ENVIRONMENT=$WORKSPACE_HOME"/environment" \
    WORKSPACE_BASE_URL="/" \
    INCLUDE_TUTORIALS="true" \
    # Main port used for sshl proxy -> can be changed
    WORKSPACE_PORT="8080" \
    # Set zsh as default shell (e.g. in jupyter)
    SHELL="/usr/bin/bash" \
    # Fix dark blue color for ls command (unreadable): 
    # https://askubuntu.com/questions/466198/how-do-i-change-the-color-for-directories-with-ls-in-the-console
    # USE default LS_COLORS - Dont set LS COLORS - overwritten in zshrc
    # LS_COLORS="" \
    # set number of threads various programs should use, if not-set, it tries to use all
    # this can be problematic since docker restricts CPUs by stil showing all
    MAX_NUM_THREADS="auto"

#### END CONFIGURATION ####

EXPOSE 8080

WORKDIR /home/${USER_NAME}

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
# CMD ["start-notebook.sh"]
CMD ["python", "/resources/docker-entrypoint.py"] 

