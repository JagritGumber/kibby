use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::assets;
use crate::config::KibbyConfig;
use crate::error::{KibbyError, Result};
use crate::paths::KibbyPaths;
use crate::probe::Probe;

pub const FOUNDATION_VERSION: &str = "0.1.0";

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Adapter {
    Arch,
    Cachyos,
    Generic,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum HyprlandDialect {
    Plain,
    CachyosLua,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PlannedFile {
    pub path: PathBuf,
    pub ownership: String,
    pub mode: u32,
    pub replaces_existing: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FoundationPlan {
    pub schema_version: u32,
    pub action: String,
    pub adapter: Adapter,
    pub dialect: HyprlandDialect,
    pub entrypoint: PathBuf,
    pub use_uwsm: bool,
    pub required_commands: Vec<String>,
    pub missing_commands: Vec<String>,
    pub packages_to_install: Vec<String>,
    pub files: Vec<PlannedFile>,
    pub bindings: Vec<String>,
    pub warnings: Vec<String>,
}

pub fn build_foundation_plan(
    config: &KibbyConfig,
    paths: &KibbyPaths,
    probe: &impl Probe,
) -> Result<FoundationPlan> {
    config.validate()?;
    let (dialect, entrypoint) = detect_dialect(paths)?;
    let adapter = detect_adapter(config, probe)?;
    let use_uwsm = match config.foundation.uwsm.as_str() {
        "always" => true,
        "never" => false,
        "auto" => probe.command_exists("uwsm") || probe.env_present("UWSM_ID"),
        _ => unreachable!("validated configuration"),
    };
    let required_commands = vec![
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
    .collect::<Vec<_>>();
    let missing_commands = required_commands
        .iter()
        .filter(|command| !probe.command_exists(command))
        .cloned()
        .collect::<Vec<_>>();
    let packages_to_install = packages_for_commands(adapter, &missing_commands)?;

    let foundation_name = match dialect {
        HyprlandDialect::Plain => "foundation.conf",
        HyprlandDialect::CachyosLua => "foundation.lua",
    };
    let destinations = [
        (paths.config_file(), "kibby", 0o644),
        (paths.lock_file(), "kibby", 0o644),
        (
            paths.hyprland_root.join("kibby").join(foundation_name),
            "kibby",
            0o644,
        ),
        (
            paths.config_root.join("foundation/hyprlock.conf"),
            "kibby",
            0o644,
        ),
        (
            paths.data_root.join("foundation/screenshot-region"),
            "kibby",
            0o755,
        ),
        (
            paths.data_root.join("foundation/screenshot-monitor"),
            "kibby",
            0o755,
        ),
        (entrypoint.clone(), "host", 0o644),
    ];
    let files = destinations
        .into_iter()
        .map(|(path, ownership, mode)| PlannedFile {
            replaces_existing: path.exists(),
            path,
            ownership: ownership.to_owned(),
            mode,
        })
        .collect();

    let warnings = if adapter == Adapter::Generic && !missing_commands.is_empty() {
        vec!["generic adapter cannot install missing native commands".to_owned()]
    } else {
        Vec::new()
    };

    Ok(FoundationPlan {
        schema_version: 1,
        action: "initialize-foundation".to_owned(),
        adapter,
        dialect,
        entrypoint,
        use_uwsm,
        required_commands,
        missing_commands,
        packages_to_install,
        files,
        bindings: vec![
            "SUPER+Return: terminal".to_owned(),
            "SUPER+Space: launcher".to_owned(),
            "SUPER+L: lock".to_owned(),
            "SUPER+CTRL+Return: recovery terminal".to_owned(),
            "XF86Audio*: direct WirePlumber controls".to_owned(),
            "XF86MonBrightness*: direct brightness controls".to_owned(),
            "Print/SUPER+Print: direct screenshots".to_owned(),
        ],
        warnings,
    })
}

fn detect_dialect(paths: &KibbyPaths) -> Result<(HyprlandDialect, PathBuf)> {
    let lua = paths.hyprland_root.join("hyprland.lua");
    let plain = paths.hyprland_root.join("hyprland.conf");
    match (lua.is_file(), plain.is_file()) {
        (true, false) => Ok((HyprlandDialect::CachyosLua, lua)),
        (false, true) => Ok((HyprlandDialect::Plain, plain)),
        (true, true) => Err(KibbyError::Unsupported(format!(
            "both {} and {} exist; select the active Hyprland entrypoint explicitly in a future config schema",
            lua.display(),
            plain.display()
        ))),
        (false, false) => Err(KibbyError::Unsupported(format!(
            "no hyprland.conf or hyprland.lua found below {}",
            paths.hyprland_root.display()
        ))),
    }
}

fn detect_adapter(config: &KibbyConfig, probe: &impl Probe) -> Result<Adapter> {
    match config.adapter.as_str() {
        "arch" => Ok(Adapter::Arch),
        "cachyos" => Ok(Adapter::Cachyos),
        "generic" => Ok(Adapter::Generic),
        "auto" => {
            let ids = probe.os_ids();
            if ids.iter().any(|id| id == "cachyos") {
                Ok(Adapter::Cachyos)
            } else if ids.iter().any(|id| id == "arch") {
                Ok(Adapter::Arch)
            } else {
                Ok(Adapter::Generic)
            }
        }
        value => Err(KibbyError::Validation(format!("unknown adapter {value:?}"))),
    }
}

fn packages_for_commands(adapter: Adapter, commands: &[String]) -> Result<Vec<String>> {
    if adapter == Adapter::Generic {
        return Ok(Vec::new());
    }
    let mut packages = BTreeSet::new();
    for command in commands {
        let package = match command.as_str() {
            "kitty" => "kitty",
            "fuzzel" => "fuzzel",
            "hyprlock" => "hyprlock",
            "wpctl" => "wireplumber",
            "brightnessctl" => "brightnessctl",
            "grim" => "grim",
            "slurp" => "slurp",
            "wl-copy" => "wl-clipboard",
            "hyprctl" => "hyprland",
            "jq" => "jq",
            value => {
                return Err(KibbyError::Unsupported(format!(
                    "no official package mapping for command {value}"
                )));
            }
        };
        packages.insert(package.to_owned());
    }
    Ok(packages.into_iter().collect())
}

pub(crate) fn rendered_foundation(
    config: &KibbyConfig,
    paths: &KibbyPaths,
    plan: &FoundationPlan,
) -> Result<String> {
    let template = match plan.dialect {
        HyprlandDialect::Plain => assets::PLAIN_FOUNDATION,
        HyprlandDialect::CachyosLua => assets::CACHYOS_FOUNDATION,
    };
    let launch_prefix = if plan.use_uwsm { "uwsm app -- " } else { "" };
    let substitutions = [
        (
            "{{terminal}}",
            format!("{launch_prefix}{}", config.providers.terminal),
        ),
        (
            "{{launcher}}",
            format!("{launch_prefix}{}", config.providers.launcher),
        ),
        ("{{lock}}", config.providers.lock.clone()),
        (
            "{{hyprlock_config}}",
            paths
                .config_root
                .join("foundation/hyprlock.conf")
                .display()
                .to_string(),
        ),
        (
            "{{screenshot_region}}",
            paths
                .data_root
                .join("foundation/screenshot-region")
                .display()
                .to_string(),
        ),
        (
            "{{screenshot_monitor}}",
            paths
                .data_root
                .join("foundation/screenshot-monitor")
                .display()
                .to_string(),
        ),
        ("{{volume_step}}", config.foundation.volume_step.to_string()),
        (
            "{{brightness_step}}",
            config.foundation.brightness_step.to_string(),
        ),
    ];
    let mut rendered = template.to_owned();
    for (token, value) in substitutions {
        if value.contains(['\n', '\r']) {
            return Err(KibbyError::Validation(format!("unsafe value for {token}")));
        }
        rendered = rendered.replace(token, &value);
    }
    if rendered.contains("{{") {
        return Err(KibbyError::Validation(
            "foundation template has unresolved tokens".to_owned(),
        ));
    }
    Ok(rendered)
}

pub(crate) fn integration_block(paths: &KibbyPaths, dialect: HyprlandDialect) -> String {
    match dialect {
        HyprlandDialect::Plain => format!(
            "\n# >>> kibby foundation >>>\nsource = {}/kibby/foundation.conf\n# <<< kibby foundation <<<\n",
            paths.hyprland_root.display()
        ),
        HyprlandDialect::CachyosLua => {
            "\n-- >>> kibby foundation >>>\nrequire(\"kibby.foundation\")\n-- <<< kibby foundation <<<\n".to_owned()
        }
    }
}

pub(crate) fn foundation_destination(paths: &KibbyPaths, dialect: HyprlandDialect) -> PathBuf {
    let name = match dialect {
        HyprlandDialect::Plain => "foundation.conf",
        HyprlandDialect::CachyosLua => "foundation.lua",
    };
    paths.hyprland_root.join("kibby").join(name)
}

pub(crate) fn validate_manifest_asset() -> Result<()> {
    let value: serde_json::Value =
        serde_json::from_str(assets::MANIFEST).map_err(|source| KibbyError::Json {
            path: PathBuf::from("packages/foundation/package.json"),
            source,
        })?;
    if value.get("id").and_then(|item| item.as_str()) != Some("foundation") {
        return Err(KibbyError::Validation(
            "embedded foundation manifest identity is invalid".to_owned(),
        ));
    }
    Ok(())
}

pub(crate) fn read_text(path: &PathBuf) -> Result<String> {
    fs::read_to_string(path).map_err(|error| crate::error::io_error(path, error))
}
