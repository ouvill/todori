use std::process::ExitCode;

use uuid::Uuid;

const USAGE: &str = "usage: cargo run -q -p taskveil-xtask -- work-id";

fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    match (args.next().as_deref(), args.next()) {
        (Some(command), None) if command == "work-id" => {
            println!("{}", generate_work_id());
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
    }
}

fn generate_work_id() -> Uuid {
    Uuid::now_v7()
}

#[cfg(test)]
mod tests {
    use super::generate_work_id;
    use uuid::Version;

    #[test]
    fn generated_work_id_is_uuid_v7() {
        let id = generate_work_id();

        assert_eq!(id.get_version(), Some(Version::SortRand));
        assert_eq!(id.to_string().len(), 36);
        assert_eq!(id.to_string(), id.hyphenated().to_string().to_lowercase());
    }
}
