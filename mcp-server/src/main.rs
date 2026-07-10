//! `todori-mcp-server`: LLMエージェント向けTodo操作インターフェース。
//!
//! TODO: rmcp SDK による stdio トランスポートの実装は後続タスク
//! （`docs/03_技術仕様書.md` §8.2）。本バイナリは現時点では起動確認用のスタブ。

// CLIと同じく、Todoriのapplication serviceへはこの共通入口だけを使う。
use todori_client as _;

fn main() {
    println!("todori-mcp-server: stdio transport not implemented yet");
}
