FROM debian:bullseye

SHELL ["/bin/bash", "-c"]

RUN echo "install required libraries" \
    # && echo "Acquire::http::Pipeline-Depth \"0\";" > /etc/apt/apt.conf.d/99nopipelining \
    && apt-get update \
    # common
    && apt-get install -y unzip git sudo libzmq3-dev vim libncurses5-dev libcairo2 curl libsodium-dev libzmq5 python3-pip libsodium23 \
    # tslab
    build-essential cmake pkg-config libbsd-dev \
    # haskell
    libtinfo-dev libcairo2-dev libpango1.0-dev libmagic-dev libblas-dev liblapack-dev libgmp-dev libgmpxx4ldbl libgmp3-dev

RUN echo "setup user" \
    && groupadd -g 1000 sine \
    && useradd -u 1000 -g 1000 -G sudo sine \
    && echo "sine:sine" | chpasswd \
    && sudo chsh -s /bin/bash sine \
    && echo "sine ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER sine
RUN sudo mkdir -p /home/sine/install \
    && sudo chown -R 1000:1000 /home
WORKDIR /home/sine/install

RUN echo "install python & cpp kernel" \
    # =================== python & cpp ===================
    && curl -o miniconda.sh -L https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash ./miniconda.sh -b -p $HOME/miniconda \
    && source $HOME/miniconda/bin/activate && conda init \
    && conda install -y jupyterlab==3.5.2 xeus-cling==0.14.0 -c conda-forge

RUN echo "install go kernel" \
    && source $HOME/miniconda/bin/activate \
    # =================== go ===================
    && curl -L https://git.io/vQhTU | bash -s -- --version 1.16 \
    && source ~/.bashrc \
    && env GO111MODULE=on go get github.com/gopherdata/gophernotes@v0.7.1 \
    && mkdir -p ~/miniconda/share/jupyter/kernels/gophernotes \
    && cd ~/miniconda/share/jupyter/kernels/gophernotes \
    && cp "$(go env GOPATH)"/pkg/mod/github.com/gopherdata/gophernotes@v0.7.1/kernel/*  "." \
    && chmod +w ./kernel.json \
    && sed "s|gophernotes|$(go env GOPATH)/bin/gophernotes|" < kernel.json.in > kernel.json

RUN echo "install java & scala kernel" \
    && source $HOME/miniconda/bin/activate \
    # =================== java ===================
    && sudo apt-get install -y openjdk-11-jdk \
    && mkdir ~/ijava && cd ~/ijava \
    && curl -LO https://github.com/SpencerPark/IJava/releases/download/v1.3.0/ijava-1.3.0.zip \
    && unzip ijava-1.3.0.zip \
    && sudo mkdir -p /usr/local/share/jupyter && sudo chmod -R uog+rwx /usr/local/share/jupyter \
    && python3 install.py --prefix ~/miniconda/ \
    # =================== scala ===================
    && mkdir ~/scala && cd ~/scala \
    && curl -Lo coursier https://git.io/coursier-cli \
    && chmod +x coursier \
    && ./coursier launch --fork almond -- --install --global

RUN echo "install js & ts kernel" \
    # =================== javascript & typescript ===================
    && curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - \
    && sudo apt-get install -y nodejs \
    && sudo npm install -g tslab@1.0.15 \
    && source $HOME/miniconda/bin/activate \
    && tslab install --python=python3 \
    # https://stackoverflow.com/questions/74796706/node-application-doesnt-start-with-zeromq-node-undefined-symbol-sodium-init
    && sudo rm -rf /usr/lib/node_modules/tslab/node_modules/zeromq \
    && sudo npm i -g zeromq@6.0.0-beta.16 --zmq-shared

RUN echo "install racket kernel" \
    && source $HOME/miniconda/bin/activate \
    # =================== racket ===================
    && curl -o racket.sh -L https://mirror.racket-lang.org/installers/8.0/racket-8.0-x86_64-linux-cs.sh \
    && sudo bash ./racket.sh --unix-style --dest /usr \
    && sudo raco pkg install -i --auto iracket \
    && raco iracket install

RUN echo "install haskell kernel" \
    # =================== haskell ===================
    && curl -sSL https://get.haskellstack.org/ | sh \
    && git clone https://github.com/gibiansky/IHaskell && cd IHaskell \
    && stack install --fast \
    && source $HOME/miniconda/bin/activate \
    && ~/.local/bin/ihaskell install --stack

# https://github.com/IHaskell/IHaskell/issues/1251
RUN mkdir -p /home/sine/.stack/global-project/ \
    && head -n 2 IHaskell/stack.yaml > ~/.stack/global-project/stack.yaml \
    && echo "packages: []" >> ~/.stack/global-project/stack.yaml

RUN echo "install rust kernel" \
    # =================== rust ===================
    && source $HOME/miniconda/bin/activate \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && source "$HOME/.cargo/env" \
    && cargo install evcxr_jupyter \
    && ~/.cargo/bin/evcxr_jupyter --install

RUN echo "install code server" \
    # =================== code server ===================
    && curl -fsSL https://code-server.dev/install.sh | sh \
    && code-server --install-extension ms-python.python

RUN echo "clean up" \
    # =================== clean up ===================
    && source $HOME/miniconda/bin/activate \
    && rm -rf $HOME/install \
    && conda clean --all -y \
    && sudo apt-get clean

EXPOSE 8080 8081
VOLUME /data
WORKDIR /data

CMD source ~/miniconda/bin/activate \
    && export JUPYTER_TOKEN=${TOKEN} \
    && export PASSWORD=${TOKEN} \
    && code-server . --bind-addr 0.0.0.0:8080 --auth password \
    & ~/miniconda/bin/jupyter lab --allow-root --no-browser --ip=0.0.0.0 --port=8081 \
    && fg
