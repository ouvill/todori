# syntax=docker/dockerfile:1
# todori-server: AWS Lambda Web Adapter (LWA) + distroless によるコンテナイメージ。
# 構成の根拠は docs/03_技術仕様書.md §1.5 を参照。
# 本イメージはLambda固有コードを含まない通常のHTTPサーバーであり、
# ECS / Fly.io 等へも同一イメージでそのまま移設可能。

FROM rust:slim AS builder
WORKDIR /build

# ワークスペース全体をコピーしてビルド（core/ crate群への依存を解決するため）。
COPY Cargo.toml rust-toolchain.toml ./
COPY core ./core
COPY cli ./cli
COPY mcp-server ./mcp-server
COPY server ./server

RUN cargo build --release -p todori-server

FROM gcr.io/distroless/cc-debian12 AS runtime

# AWS Lambda Web Adapter: Lambdaイベント <-> HTTPリクエストの変換を担う。
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

COPY --from=builder /build/target/release/todori-server /usr/local/bin/todori-server

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/todori-server"]
