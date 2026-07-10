//! `todori-mcp-server`: LLMエージェント向けTodo操作インターフェース。
//!
//! TODO: rmcp SDK による stdio トランスポートの実装は後続タスク
//! （`docs/03_技術仕様書.md` §8.2）。本バイナリは現時点では起動確認用のスタブ。

// CLIと同じく、Todoriのapplication serviceへはこの共通入口だけを使う。
use todori_client::{ClientError, LocalProfileConfig, TodoriClient};

const _: fn(LocalProfileConfig) -> Result<TodoriClient, ClientError> = TodoriClient::open;

#[allow(dead_code)]
fn _assert_async_client_api(client: &TodoriClient) {
    std::mem::drop(client.sync_now());
}

fn main() {
    println!("todori-mcp-server: stdio transport not implemented yet");
}
