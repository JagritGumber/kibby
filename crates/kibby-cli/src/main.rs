use std::io::{self, Write};
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use kibby_core::{
    CommandRunner, HostProbe, KibbyConfig, KibbyError, KibbyPaths, Probe, apply_foundation,
    build_foundation_plan, doctor, recover_latest,
};

#[derive(Debug, Parser)]
#[command(
    name = "kibby",
    version,
    about = "Source-owning components for existing Hyprland desktops"
)]
struct Cli {
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Preview and initialize the direct recovery foundation.
    Init {
        /// Print the complete transaction without changing packages or files.
        #[arg(long)]
        dry_run: bool,
        /// Apply without the interactive confirmation prompt.
        #[arg(long)]
        yes: bool,
    },
    /// Print the transaction that init would apply.
    Plan,
    /// Check foundation files, commands, and Hyprland integration.
    Doctor,
    /// Restore files from the latest unrecovered transaction.
    Recover {
        #[arg(long)]
        yes: bool,
    },
    /// List the optional component commands planned after foundation validation.
    Components,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("kibby: {error}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<ExitCode, KibbyError> {
    let cli = Cli::parse();
    let probe = HostProbe;
    let runner = CommandRunner;
    let default = KibbyConfig::default();
    let initial_paths = KibbyPaths::discover(&default)?;
    let config = if initial_paths.config_file().is_file() {
        KibbyConfig::load(&initial_paths.config_file())?
    } else {
        default
    };
    let paths = KibbyPaths::discover(&config)?;
    let live_reload =
        probe.env_present("HYPRLAND_INSTANCE_SIGNATURE") && probe.command_exists("hyprctl");

    match cli.command {
        Command::Init { dry_run, yes } => {
            let plan = build_foundation_plan(&config, &paths, &probe)?;
            print_value(&plan, cli.json)?;
            if dry_run {
                return Ok(ExitCode::SUCCESS);
            }
            confirm("Apply this foundation transaction?", yes)?;
            let result = apply_foundation(&config, &paths, &plan, &runner, live_reload)?;
            print_value(&result, cli.json)?;
            Ok(ExitCode::SUCCESS)
        }
        Command::Plan => {
            let plan = build_foundation_plan(&config, &paths, &probe)?;
            print_value(&plan, cli.json)?;
            Ok(ExitCode::SUCCESS)
        }
        Command::Doctor => {
            let report = doctor(&paths, &probe);
            print_value(&report, cli.json)?;
            Ok(if report.healthy {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            })
        }
        Command::Recover { yes } => {
            confirm("Restore files from the latest Kibby transaction?", yes)?;
            let result = recover_latest(&paths, &runner, live_reload)?;
            print_value(&result, cli.json)?;
            Ok(ExitCode::SUCCESS)
        }
        Command::Components => {
            println!(
                "Optional component add/diff/update commands unlock after foundation v1 validation."
            );
            Ok(ExitCode::SUCCESS)
        }
    }
}

fn confirm(prompt: &str, assume_yes: bool) -> Result<(), KibbyError> {
    if assume_yes {
        return Ok(());
    }
    print!("{prompt} [y/N] ");
    io::stdout()
        .flush()
        .map_err(|error| KibbyError::Command(format!("could not show confirmation: {error}")))?;
    let mut answer = String::new();
    io::stdin()
        .read_line(&mut answer)
        .map_err(|error| KibbyError::Command(format!("could not read confirmation: {error}")))?;
    if matches!(answer.trim().to_ascii_lowercase().as_str(), "y" | "yes") {
        Ok(())
    } else {
        Err(KibbyError::Command("transaction cancelled".to_owned()))
    }
}

fn print_value(value: &impl serde::Serialize, json: bool) -> Result<(), KibbyError> {
    if json {
        let text = serde_json::to_string_pretty(value)
            .map_err(|error| KibbyError::Command(format!("could not serialize output: {error}")))?;
        println!("{text}");
    } else {
        let value = serde_json::to_value(value)
            .map_err(|error| KibbyError::Command(format!("could not serialize output: {error}")))?;
        if let Some(action) = value.get("action").and_then(|item| item.as_str()) {
            println!("Action: {action}");
        }
        println!(
            "{}",
            serde_json::to_string_pretty(&value).map_err(|error| KibbyError::Command(format!(
                "could not serialize output: {error}"
            )))?
        );
    }
    Ok(())
}
