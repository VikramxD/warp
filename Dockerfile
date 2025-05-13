# syntax=docker/dockerfile:1.4   # Enables BuildKit features if your local Docker needs the hint

############################################
# Stage 1 – build Python wheels & JS assets
############################################
FROM python:3-slim AS compile-image

ENV NODE_VER=16.3.0
WORKDIR /opt/warp

# 1️⃣ Build deps for Python + Node
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget mime-support build-essential libpq-dev libpcre3-dev && \
    rm -rf /var/lib/apt/lists/*

# 2️⃣ Lightweight Node install (no apt repo)
RUN NODE_ARCH=$(uname -m | sed \
        's/^x86_64\|amd64$/x64/;s/^i.*86$/x86/;s/^aarch64$/arm64/') && \
    NODE_URL="https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-${NODE_ARCH}.tar.gz" && \
    wget -qO- "$NODE_URL" | tar -xz --strip-components=1 -C /usr/

# 3️⃣ Python build tooling + wheel cache
RUN pip install --upgrade pip setuptools wheel uwsgi && \
    pip wheel -w /opt/warp/wheel/ uwsgi

#####################
# Build JS (Webpack)
#####################
WORKDIR /opt/warp/js/
COPY js/package.json js/package-lock.json ./
RUN npm ci
COPY js/ ./
RUN npm run build

#############################
# Build Python package wheel
#############################
WORKDIR /opt/warp
COPY requirements.txt ./
RUN pip wheel -w /opt/warp/wheel -r requirements.txt

COPY warp ./warp
COPY setup.py MANIFEST.in ./
RUN python setup.py bdist_wheel -d /opt/warp/wheel

#################################
# Stage 2 – slim runtime image
#################################
FROM python:3-slim
WORKDIR /opt/warp

# Runtime libs only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpq5 mime-support libpcre3 && \
    rm -rf /var/lib/apt/lists/*

# 4️⃣ Bring wheels across *once* (COPY works everywhere)
COPY --from=compile-image /opt/warp/wheel /tmp/wheel
RUN pip install --no-index /tmp/wheel/*.whl && \
    rm -rf /tmp/wheel    # keep final image small

# 5️⃣ Static assets + uWSGI config
COPY --from=compile-image /opt/warp/warp/static ./static
COPY res/warp_uwsgi.ini .

EXPOSE 8000
ENTRYPOINT ["uwsgi", "warp_uwsgi.ini"]

