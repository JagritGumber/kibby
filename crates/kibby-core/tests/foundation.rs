use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;

use kibby_core::{
    Adapter, CommandRunner, KibbyConfig, KibbyPaths, Probe, ProcessResult, Result, Runner,
    apply_foundation, build_foundation_plan, doctor, recover_latest,
};

struct FakeProbe {
    commands: BTreeSet<String>,
    ids: Vec<String>,
    uwsm: bool,
}

impl FakeProbe {
    fn complete(ids: &[&str]) -> Self {
        Self {
            commands: [
                "kitty",
                "fuzzel",
                "hyprlock",
                "wpctl",
                "brightnessctl",
                "grim",
                "slurp",
                "wl-copy",
                "hyprctl",
                "jq",
            ]
            .into_iter()
            .map(str::to_owned)
            .collect(),
            ids: ids.iter().map(|value| (*value).to_owned()).collect(),
            uwsm: true,
        }
    }
}

impl Probe for FakeProbe {
    fn command_exists(&self, command: &str) -> bool {
        self.commands.contains(command)
    }

    fn os_ids(&self) -> Vec<String> {
        self.ids.clone()
    }

    fn env_present(&self, name: &str) -> bool {
        name == "UWSM_ID" && self.uwsm
    }
}

struct FakeRunner;

impl Runner for FakeRunner {
    fn run(&self, program: &str, arguments: &[String]) -> Result<ProcessResult> {
        let stdout = if program == "pacman" && arguments.first().map(String::as_str) == Some("-Q") {
            format!("{} 1.0.0\n", arguments.get(1).unwrap())
        } else {
            String::new()
        };
        Ok(ProcessResult {
            success: true,
            stdout,
            stderr: String::new(),
        })
    }
}

struct PackageFailureRunner;

impl Runner for PackageFailureRunner {
    fn run(&self, program: &str, arguments: &[String]) -> Result<ProcessResult> {
        assert_eq!(program, "pkexec");
        assert_eq!(arguments.first().map(String::as_str), Some("pacman"));
        Ok(ProcessResult {
            success: false,
            stdout: String::new(),
            stderr: "fixture package failure".to_owned(),
        })
    }
}

struct ConfigErrorRunner;

impl Runner for ConfigErrorRunner {
    fn run(&self, program: &str, arguments: &[String]) -> Result<ProcessResult> {
        let is_config_check =
            program == "hyprctl" && arguments.first().map(String::as_str) == Some("configerrors");
        Ok(ProcessResult {
            success: true,
            stdout: if is_config_check {
                "fixture config error".to_owned()
            } else if program == "pacman" {
                format!("{} 1.0.0\n", arguments.get(1).unwrap())
            } else {
                String::new()
            },
            stderr: String::new(),
        })
    }
}

fn setup_home(lua: bool) -> (tempfile::TempDir, KibbyConfig, KibbyPaths, PathBuf) {
    let temporary = tempfile::tempdir().unwrap();
    let home = temporary.path().join("home");
    let mut config = KibbyConfig::default();
    config.foundation.uwsm = "always".to_owned();
    let paths = KibbyPaths::for_home(&config, home).unwrap();
    fs::create_dir_all(&paths.hyprland_root).unwrap();
    let entrypoint = paths
        .hyprland_root
        .join(if lua { "hyprland.lua" } else { "hyprland.conf" });
    fs::write(
        &entrypoint,
        if lua {
            "require(\"config.binds\")\n"
        } else {
            "general { }\n"
        },
    )
    .unwrap();
    (temporary, config, paths, entrypoint)
}

#[test]
fn detects_plain_arch_and_exact_files() {
    let (_temporary, config, paths, _entrypoint) = setup_home(false);
    let plan = build_foundation_plan(&config, &paths, &FakeProbe::complete(&["arch"])).unwrap();
    assert_eq!(plan.adapter, Adapter::Arch);
    assert!(plan.packages_to_install.is_empty());
    assert!(
        plan.files
            .iter()
            .any(|file| file.path.ends_with("foundation.conf"))
    );
}

#[test]
fn applies_and_recovers_cachyos_without_quickshell() {
    let (_temporary, config, paths, entrypoint) = setup_home(true);
    let original = fs::read_to_string(&entrypoint).unwrap();
    let probe = FakeProbe::complete(&["cachyos", "arch"]);
    let plan = build_foundation_plan(&config, &paths, &probe).unwrap();
    let result = apply_foundation(&config, &paths, &plan, &FakeRunner, false).unwrap();

    assert!(!result.live_reload);
    assert!(paths.config_file().is_file());
    assert!(paths.lock_file().is_file());
    assert!(paths.hyprland_root.join("kibby/foundation.lua").is_file());
    assert!(
        fs::read_to_string(&entrypoint)
            .unwrap()
            .contains("require(\"kibby.foundation\")")
    );
    let source = fs::read_to_string(paths.hyprland_root.join("kibby/foundation.lua")).unwrap();
    assert!(source.contains("wpctl set-volume"));
    assert!(source.contains("uwsm app -- kitty"));
    assert!(!source.contains("quickshell"));
    assert!(doctor(&paths, &probe).healthy);

    let recovery = recover_latest(&paths, &FakeRunner, false).unwrap();
    assert_eq!(recovery.transaction_id, result.transaction_id);
    assert_eq!(fs::read_to_string(&entrypoint).unwrap(), original);
    assert!(!paths.config_file().exists());
    assert!(!paths.hyprland_root.join("kibby/foundation.lua").exists());
}

#[test]
fn generic_adapter_refuses_missing_commands_before_writes() {
    let (_temporary, mut config, paths, _entrypoint) = setup_home(false);
    config.adapter = "generic".to_owned();
    let probe = FakeProbe {
        commands: BTreeSet::new(),
        ids: vec!["fedora".to_owned()],
        uwsm: false,
    };
    let plan = build_foundation_plan(&config, &paths, &probe).unwrap();
    let error = apply_foundation(&config, &paths, &plan, &CommandRunner, false).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("generic adapter is missing commands")
    );
    assert!(!paths.config_file().exists());
}

#[test]
fn config_rejects_shell_injection_as_provider() {
    let mut config = KibbyConfig::default();
    config.providers.terminal = "kitty; rm -rf /".to_owned();
    assert!(config.validate().is_err());
}

#[test]
fn package_failure_happens_before_any_configuration_write() {
    let (_temporary, config, paths, entrypoint) = setup_home(false);
    let original = fs::read(&entrypoint).unwrap();
    let probe = FakeProbe {
        commands: BTreeSet::new(),
        ids: vec!["arch".to_owned()],
        uwsm: false,
    };
    let plan = build_foundation_plan(&config, &paths, &probe).unwrap();

    let error = apply_foundation(&config, &paths, &plan, &PackageFailureRunner, false).unwrap_err();

    assert!(error.to_string().contains("before configuration changed"));
    assert_eq!(fs::read(&entrypoint).unwrap(), original);
    assert!(!paths.config_root.exists());
    assert!(!paths.state_root.exists());
}

#[test]
fn failed_live_validation_restores_all_targets_and_is_not_recoverable() {
    let (_temporary, config, paths, entrypoint) = setup_home(false);
    let original = fs::read(&entrypoint).unwrap();
    let plan = build_foundation_plan(&config, &paths, &FakeProbe::complete(&["arch"])).unwrap();

    let error = apply_foundation(&config, &paths, &plan, &ConfigErrorRunner, true).unwrap_err();

    assert!(error.to_string().contains("fixture config error"));
    assert_eq!(fs::read(&entrypoint).unwrap(), original);
    assert!(!paths.config_file().exists());
    assert!(!paths.lock_file().exists());
    assert!(!paths.hyprland_root.join("kibby/foundation.conf").exists());
    let transactions = fs::read_dir(paths.transactions())
        .unwrap()
        .collect::<Vec<_>>();
    assert_eq!(transactions.len(), 1);
    assert!(
        transactions[0]
            .as_ref()
            .unwrap()
            .path()
            .join("rolled-back")
            .is_file()
    );
    assert!(recover_latest(&paths, &FakeRunner, false).is_err());
}

#[test]
fn repeated_init_keeps_exactly_one_integration_marker() {
    let (_temporary, config, paths, entrypoint) = setup_home(false);
    let plan = build_foundation_plan(&config, &paths, &FakeProbe::complete(&["arch"])).unwrap();

    apply_foundation(&config, &paths, &plan, &FakeRunner, false).unwrap();
    apply_foundation(&config, &paths, &plan, &FakeRunner, false).unwrap();

    let text = fs::read_to_string(entrypoint).unwrap();
    assert_eq!(text.matches("# >>> kibby foundation >>>").count(), 1);
    assert_eq!(text.matches("# <<< kibby foundation <<<").count(), 1);
}

#[test]
fn explicit_home_keeps_all_owned_paths_below_that_home() {
    let temporary = tempfile::tempdir().unwrap();
    let home = temporary.path().join("canary-home");
    let paths = KibbyPaths::for_home(&KibbyConfig::default(), home.clone()).unwrap();

    for path in [
        &paths.config_root,
        &paths.state_root,
        &paths.data_root,
        &paths.hyprland_root,
        &paths.quickshell_root,
    ] {
        assert!(
            path.starts_with(&home),
            "{} escaped canary HOME",
            path.display()
        );
    }
}
