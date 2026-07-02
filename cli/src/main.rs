//! `todori` CLI。
//!
//! `core` crate群を通じてローカルの暗号化DBへ直接アクセスする設計だが
//! （`docs/03_技術仕様書.md` §8.1, §8.3）、DB統合前の現段階ではスタブとして
//! サブコマンドの受け口のみを提供する。

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "todori", version, about = "Todori: E2EE Todo CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// 新規タスクを追加する。
    Add { title: String },
    /// タスク一覧を表示する。
    List,
    /// タスクを完了状態にする。
    Done { id: String },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Command::Add { title } => {
            println!("add \"{title}\": not implemented yet");
        }
        Command::List => {
            println!("list: not implemented yet");
        }
        Command::Done { id } => {
            println!("done {id}: not implemented yet");
        }
    }
}
