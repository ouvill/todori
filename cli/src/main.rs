//! `todori` CLI。
//!
//! `todori-client`の共通profile APIを通じてローカルの暗号化DBへ直接アクセスする設計だが
//! （`docs/03_技術仕様書.md` §8.1, §8.3）、DB統合前の現段階ではスタブとして
//! サブコマンドの受け口のみを提供する。

use clap::{Parser, Subcommand};

// `todori-client`をfrontend共通入口としてcompile時にも固定する。実際の
// profile openとsubcommand接続はOS secret store実装後の後続taskで行う。
use todori_client::{ClientError, ClientProfile, ProfileConfig};

const _: fn(ProfileConfig) -> Result<ClientProfile, ClientError> = ClientProfile::open;

#[allow(dead_code)]
fn _assert_async_profile_api(profile: &ClientProfile) {
    std::mem::drop(profile.sync_now());
}

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
