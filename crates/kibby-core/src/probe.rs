use std::env;
use std::path::PathBuf;
use std::process::Command;

use crate::error::{KibbyError, Result};

pub trait Probe {
    fn command_exists(&self, command: &str) -> bool;
    fn os_ids(&self) -> Vec<String>;
    fn env_present(&self, name: &str) -> bool;
}

#[derive(Debug, Default)]
pub struct HostProbe;

impl Probe for HostProbe {
    fn command_exists(&self, command: &str) -> bool {
        let Some(path) = env::var_os("PATH") else {
            return false;
        };
        env::split_paths(&path).any(|directory| directory.join(command).is_file())
    }

    fn os_ids(&self) -> Vec<String> {
        let path = env::var_os("KIBBY_OS_RELEASE")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/etc/os-release"));
        let Ok(text) = std::fs::read_to_string(path) else {
            return Vec::new();
        };
        let mut ids = Vec::new();
        for line in text.lines() {
            if let Some(value) = line.strip_prefix("ID=") {
                ids.push(unquote(value).to_owned());
            } else if let Some(value) = line.strip_prefix("ID_LIKE=") {
                ids.extend(unquote(value).split_whitespace().map(str::to_owned));
            }
        }
        ids
    }

    fn env_present(&self, name: &str) -> bool {
        env::var_os(name).is_some()
    }
}

fn unquote(value: &str) -> &str {
    value
        .strip_prefix('"')
        .and_then(|inner| inner.strip_suffix('"'))
        .unwrap_or(value)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessResult {
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
}

pub trait Runner {
    fn run(&self, program: &str, arguments: &[String]) -> Result<ProcessResult>;
}

#[derive(Debug, Default)]
pub struct CommandRunner;

impl Runner for CommandRunner {
    fn run(&self, program: &str, arguments: &[String]) -> Result<ProcessResult> {
        let output = Command::new(program)
            .args(arguments)
            .output()
            .map_err(|error| KibbyError::Command(format!("could not run {program}: {error}")))?;
        Ok(ProcessResult {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}
