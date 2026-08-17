use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::assets;
use crate::config::KibbyConfig;
use crate::error::{KibbyError, Result, io_error};
use crate::foundation::{
    Adapter, FOUNDATION_VERSION, FoundationPlan, HyprlandDialect, foundation_destination,
    integration_block, read_text, rendered_foundation, validate_manifest_asset,
};
use crate::paths::KibbyPaths;
use crate::probe::{Probe, Runner};

const PLAIN_BEGIN: &str = "# >>> kibby foundation >>>";
const PLAIN_END: &str = "# <<< kibby foundation <<<";
const LUA_BEGIN: &str = "-- >>> kibby foundation >>>";
const LUA_END: &str = "-- <<< kibby foundation <<<";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ApplyResult {
    pub transaction_id: String,
    pub foundation_version: String,
    pub files_written: Vec<PathBuf>,
    pub packages_installed: Vec<String>,
    pub live_reload: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryResult {
    pub transaction_id: String,
    pub restored: Vec<PathBuf>,
    pub removed: Vec<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DoctorCheck {
    pub name: String,
    pub ok: bool,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DoctorReport {
    pub healthy: bool,
    pub checks: Vec<DoctorCheck>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransactionManifest {
    schema_version: u32,
    transaction_id: String,
    entries: Vec<BackupEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BackupEntry {
    path: PathBuf,
    existed: bool,
    backup: Option<String>,
    original_mode: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LockFile {
    schema_version: u32,
    foundation: LockedFoundation,
    components: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LockedFoundation {
    version: String,
    adapter: Adapter,
    dialect: HyprlandDialect,
    manifest_hash: String,
    files: std::collections::BTreeMap<String, String>,
    native_versions: std::collections::BTreeMap<String, String>,
}

pub fn apply_foundation(
    config: &KibbyConfig,
    paths: &KibbyPaths,
    plan: &FoundationPlan,
    runner: &impl Runner,
    live_reload: bool,
) -> Result<ApplyResult> {
    validate_manifest_asset()?;
    if plan.adapter == Adapter::Generic && !plan.missing_commands.is_empty() {
        return Err(KibbyError::Unsupported(format!(
            "generic adapter is missing commands: {}",
            plan.missing_commands.join(", ")
        )));
    }

    if !plan.packages_to_install.is_empty() {
        let mut arguments = vec![
            "pacman".to_owned(),
            "-S".to_owned(),
            "--needed".to_owned(),
            "--noconfirm".to_owned(),
        ];
        arguments.extend(plan.packages_to_install.iter().cloned());
        let result = runner.run("pkexec", &arguments)?;
        if !result.success {
            return Err(KibbyError::Command(format!(
                "official package transaction failed before configuration changed: {}",
                result.stderr.trim()
            )));
        }
    }

    let transaction_id = transaction_id();
    let transaction_root = paths.transactions().join(&transaction_id);
    let targets = transaction_targets(paths, plan);
    let manifest = back_up_targets(&transaction_root, &transaction_id, &targets)?;

    let result = (|| {
        config.validate()?;
        atomic_write(
            &paths.config_file(),
            config.pretty_json()?.as_bytes(),
            0o644,
        )?;

        let rendered = rendered_foundation(config, paths, plan)?;
        let foundation_path = foundation_destination(paths, plan.dialect);
        atomic_write(&foundation_path, rendered.as_bytes(), 0o644)?;
        atomic_write(
            &paths.config_root.join("foundation/hyprlock.conf"),
            assets::HYPRLOCK.as_bytes(),
            0o644,
        )?;
        atomic_write(
            &paths.data_root.join("foundation/screenshot-region"),
            assets::SCREENSHOT_REGION.as_bytes(),
            0o755,
        )?;
        atomic_write(
            &paths.data_root.join("foundation/screenshot-monitor"),
            assets::SCREENSHOT_MONITOR.as_bytes(),
            0o755,
        )?;

        let entrypoint_text = read_text(&plan.entrypoint)?;
        let integrated = install_integration_block(
            &entrypoint_text,
            &integration_block(paths, plan.dialect),
            plan.dialect,
        )?;
        atomic_write(&plan.entrypoint, integrated.as_bytes(), 0o644)?;

        validate_written_files(paths, plan)?;
        if live_reload {
            let reload = runner.run("hyprctl", &["reload".to_owned()])?;
            if !reload.success {
                return Err(KibbyError::Command(format!(
                    "Hyprland reload failed: {}",
                    reload.stderr.trim()
                )));
            }
            let errors = runner.run("hyprctl", &["configerrors".to_owned()])?;
            if !errors.success || !errors.stdout.trim().is_empty() {
                return Err(KibbyError::Validation(format!(
                    "Hyprland reported configuration errors: {}{}",
                    errors.stdout.trim(),
                    errors.stderr.trim()
                )));
            }
        }

        let lock = build_lock(plan, runner)?;
        let mut lock_text =
            serde_json::to_string_pretty(&lock).map_err(|source| KibbyError::Json {
                path: paths.lock_file(),
                source,
            })?;
        lock_text.push('\n');
        atomic_write(&paths.lock_file(), lock_text.as_bytes(), 0o644)?;
        Ok(())
    })();

    if let Err(error) = result {
        let rollback = restore_manifest(&transaction_root, &manifest);
        if rollback.is_ok() {
            let _ = atomic_write(
                &transaction_root.join("rolled-back"),
                b"rolled-back\n",
                0o644,
            );
        }
        if live_reload {
            let _ = runner.run("hyprctl", &["reload".to_owned()]);
        }
        return match rollback {
            Ok(_) => Err(error),
            Err(rollback_error) => Err(KibbyError::Validation(format!(
                "{error}; rollback also failed: {rollback_error}"
            ))),
        };
    }

    atomic_write(
        &transaction_root.join("applied"),
        format!("{transaction_id}\n").as_bytes(),
        0o644,
    )?;
    Ok(ApplyResult {
        transaction_id,
        foundation_version: FOUNDATION_VERSION.to_owned(),
        files_written: targets,
        packages_installed: plan.packages_to_install.clone(),
        live_reload,
    })
}

pub fn recover_latest(
    paths: &KibbyPaths,
    runner: &impl Runner,
    live_reload: bool,
) -> Result<RecoveryResult> {
    let root = paths.transactions();
    let mut candidates = fs::read_dir(&root)
        .map_err(|error| io_error(&root, error))?
        .filter_map(std::result::Result::ok)
        .filter(|entry| {
            let path = entry.path();
            path.is_dir() && path.join("applied").is_file() && !path.join("recovered").exists()
        })
        .collect::<Vec<_>>();
    candidates.sort_by_key(|entry| entry.file_name());
    let transaction = candidates.pop().ok_or(KibbyError::NothingToRecover)?.path();
    let manifest_path = transaction.join("manifest.json");
    let text =
        fs::read_to_string(&manifest_path).map_err(|error| io_error(&manifest_path, error))?;
    let manifest: TransactionManifest =
        serde_json::from_str(&text).map_err(|source| KibbyError::Json {
            path: manifest_path,
            source,
        })?;
    let result = restore_manifest(&transaction, &manifest)?;
    atomic_write(&transaction.join("recovered"), b"recovered\n", 0o644)?;
    if live_reload {
        let reload = runner.run("hyprctl", &["reload".to_owned()])?;
        if !reload.success {
            return Err(KibbyError::Command(format!(
                "files recovered but Hyprland reload failed: {}",
                reload.stderr.trim()
            )));
        }
    }
    Ok(result)
}

pub fn doctor(paths: &KibbyPaths, probe: &impl Probe) -> DoctorReport {
    let mut checks = Vec::new();
    let config_path = paths.config_file();
    checks.push(check_file("config", &config_path));
    checks.push(check_file("lock", &paths.lock_file()));

    if let Ok(config) = KibbyConfig::load(&config_path) {
        let lua = paths.hyprland_root.join("hyprland.lua");
        let plain = paths.hyprland_root.join("hyprland.conf");
        let (entrypoint, marker, foundation) = if lua.is_file() {
            (
                lua,
                LUA_BEGIN,
                paths.hyprland_root.join("kibby/foundation.lua"),
            )
        } else {
            (
                plain,
                PLAIN_BEGIN,
                paths.hyprland_root.join("kibby/foundation.conf"),
            )
        };
        checks.push(check_file("foundation-source", &foundation));
        let include_ok = fs::read_to_string(&entrypoint).is_ok_and(|text| text.contains(marker));
        checks.push(DoctorCheck {
            name: "hyprland-integration".to_owned(),
            ok: include_ok,
            detail: entrypoint.display().to_string(),
        });
        for command in [
            config.providers.terminal.as_str(),
            config.providers.launcher.as_str(),
            config.providers.lock.as_str(),
            "wpctl",
            "brightnessctl",
            "grim",
            "slurp",
            "wl-copy",
            "hyprctl",
            "jq",
        ] {
            checks.push(DoctorCheck {
                name: format!("command:{command}"),
                ok: probe.command_exists(command),
                detail: command.to_owned(),
            });
        }
    }
    DoctorReport {
        healthy: checks.iter().all(|check| check.ok),
        checks,
    }
}

fn transaction_targets(paths: &KibbyPaths, plan: &FoundationPlan) -> Vec<PathBuf> {
    vec![
        paths.config_file(),
        paths.lock_file(),
        foundation_destination(paths, plan.dialect),
        paths.config_root.join("foundation/hyprlock.conf"),
        paths.data_root.join("foundation/screenshot-region"),
        paths.data_root.join("foundation/screenshot-monitor"),
        plan.entrypoint.clone(),
    ]
}

fn back_up_targets(
    root: &Path,
    transaction_id: &str,
    targets: &[PathBuf],
) -> Result<TransactionManifest> {
    fs::create_dir_all(root).map_err(|error| io_error(root, error))?;
    let backup_root = root.join("files");
    fs::create_dir_all(&backup_root).map_err(|error| io_error(&backup_root, error))?;
    let mut entries = Vec::new();
    for (index, path) in targets.iter().enumerate() {
        if path.exists() {
            if !path.is_file() {
                return Err(KibbyError::Validation(format!(
                    "refusing to replace non-file path {}",
                    path.display()
                )));
            }
            let name = format!("{index:03}.backup");
            let backup = backup_root.join(&name);
            fs::copy(path, &backup).map_err(|error| io_error(&backup, error))?;
            entries.push(BackupEntry {
                path: path.clone(),
                existed: true,
                backup: Some(format!("files/{name}")),
                original_mode: existing_mode(path),
            });
        } else {
            entries.push(BackupEntry {
                path: path.clone(),
                existed: false,
                backup: None,
                original_mode: None,
            });
        }
    }
    let manifest = TransactionManifest {
        schema_version: 1,
        transaction_id: transaction_id.to_owned(),
        entries,
    };
    let mut text = serde_json::to_string_pretty(&manifest).map_err(|source| KibbyError::Json {
        path: root.join("manifest.json"),
        source,
    })?;
    text.push('\n');
    atomic_write(&root.join("manifest.json"), text.as_bytes(), 0o600)?;
    Ok(manifest)
}

fn restore_manifest(root: &Path, manifest: &TransactionManifest) -> Result<RecoveryResult> {
    let mut restored = Vec::new();
    let mut removed = Vec::new();
    for entry in manifest.entries.iter().rev() {
        if entry.existed {
            let relative = entry.backup.as_ref().ok_or_else(|| {
                KibbyError::Validation(format!("missing backup for {}", entry.path.display()))
            })?;
            let backup = root.join(relative);
            let bytes = fs::read(&backup).map_err(|error| io_error(&backup, error))?;
            atomic_write(&entry.path, &bytes, entry.original_mode.unwrap_or(0o644))?;
            restored.push(entry.path.clone());
        } else if entry.path.exists() {
            fs::remove_file(&entry.path).map_err(|error| io_error(&entry.path, error))?;
            removed.push(entry.path.clone());
        }
    }
    Ok(RecoveryResult {
        transaction_id: manifest.transaction_id.clone(),
        restored,
        removed,
    })
}

fn install_integration_block(
    original: &str,
    block: &str,
    dialect: HyprlandDialect,
) -> Result<String> {
    let (begin, end) = match dialect {
        HyprlandDialect::Plain => (PLAIN_BEGIN, PLAIN_END),
        HyprlandDialect::CachyosLua => (LUA_BEGIN, LUA_END),
    };
    let without_old = match (original.find(begin), original.find(end)) {
        (None, None) => original.trim_end().to_owned(),
        (Some(start), Some(end_start)) if start < end_start => {
            let after = end_start + end.len();
            format!(
                "{}{}",
                original[..start].trim_end(),
                original[after..].trim_start()
            )
            .trim_end()
            .to_owned()
        }
        _ => {
            return Err(KibbyError::Validation(
                "malformed existing Kibby foundation marker block".to_owned(),
            ));
        }
    };
    Ok(format!("{without_old}{}", block))
}

fn validate_written_files(paths: &KibbyPaths, plan: &FoundationPlan) -> Result<()> {
    let foundation = foundation_destination(paths, plan.dialect);
    let source = fs::read_to_string(&foundation).map_err(|error| io_error(&foundation, error))?;
    if source.contains("{{") {
        return Err(KibbyError::Validation(format!(
            "unresolved template token in {}",
            foundation.display()
        )));
    }
    let entrypoint = read_text(&plan.entrypoint)?;
    let marker = match plan.dialect {
        HyprlandDialect::Plain => PLAIN_BEGIN,
        HyprlandDialect::CachyosLua => LUA_BEGIN,
    };
    if !entrypoint.contains(marker) {
        return Err(KibbyError::Validation(
            "Hyprland integration marker was not written".to_owned(),
        ));
    }
    Ok(())
}

fn build_lock(plan: &FoundationPlan, runner: &impl Runner) -> Result<LockFile> {
    let files = [
        ("hyprland/plain/foundation.conf", assets::PLAIN_FOUNDATION),
        (
            "hyprland/cachyos-lua/foundation.lua",
            assets::CACHYOS_FOUNDATION,
        ),
        ("hyprlock.conf", assets::HYPRLOCK),
        ("scripts/screenshot-region.sh", assets::SCREENSHOT_REGION),
        ("scripts/screenshot-monitor.sh", assets::SCREENSHOT_MONITOR),
    ]
    .into_iter()
    .map(|(name, contents)| (name.to_owned(), sha256(contents.as_bytes())))
    .collect();
    let mut native_versions = std::collections::BTreeMap::new();
    if plan.adapter != Adapter::Generic {
        for package in &plan.packages_to_install {
            let result = runner.run("pacman", &["-Q".to_owned(), package.clone()])?;
            if result.success {
                native_versions.insert(package.clone(), result.stdout.trim().to_owned());
            }
        }
    }
    Ok(LockFile {
        schema_version: 1,
        foundation: LockedFoundation {
            version: FOUNDATION_VERSION.to_owned(),
            adapter: plan.adapter,
            dialect: plan.dialect,
            manifest_hash: sha256(assets::MANIFEST.as_bytes()),
            files,
            native_versions,
        },
        components: serde_json::Map::new(),
    })
}

fn check_file(name: &str, path: &Path) -> DoctorCheck {
    DoctorCheck {
        name: name.to_owned(),
        ok: path.is_file(),
        detail: path.display().to_string(),
    }
}

fn transaction_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{nanos:032x}")
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn atomic_write(path: &Path, bytes: &[u8], mode: u32) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| KibbyError::Validation(format!("path has no parent: {}", path.display())))?;
    fs::create_dir_all(parent).map_err(|error| io_error(parent, error))?;
    let temporary = parent.join(format!(
        ".{}.kibby-{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("file"),
        transaction_id()
    ));
    let result = (|| {
        let mut file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)
            .map_err(|error| io_error(&temporary, error))?;
        file.write_all(bytes)
            .map_err(|error| io_error(&temporary, error))?;
        file.sync_all()
            .map_err(|error| io_error(&temporary, error))?;
        set_mode(&temporary, mode)?;
        fs::rename(&temporary, path).map_err(|error| io_error(path, error))?;
        Ok(())
    })();
    if temporary.exists() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|error| io_error(path, error))
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> Result<()> {
    Ok(())
}

#[cfg(unix)]
fn existing_mode(path: &Path) -> Option<u32> {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .ok()
        .map(|metadata| metadata.permissions().mode() & 0o777)
}

#[cfg(not(unix))]
fn existing_mode(_path: &Path) -> Option<u32> {
    Some(0o644)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integration_is_idempotent() {
        let block = "\n# >>> kibby foundation >>>\nsource = /tmp/foundation.conf\n# <<< kibby foundation <<<\n";
        let first = install_integration_block("misc { }\n", block, HyprlandDialect::Plain).unwrap();
        let second = install_integration_block(&first, block, HyprlandDialect::Plain).unwrap();
        assert_eq!(first, second);
        assert_eq!(first.matches(PLAIN_BEGIN).count(), 1);
    }

    #[test]
    fn malformed_marker_is_rejected() {
        let error =
            install_integration_block(PLAIN_BEGIN, "ignored", HyprlandDialect::Plain).unwrap_err();
        assert!(error.to_string().contains("malformed"));
    }
}
