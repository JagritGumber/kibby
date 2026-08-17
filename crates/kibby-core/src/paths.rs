use std::env;
use std::path::{Path, PathBuf};

use crate::config::KibbyConfig;
use crate::error::{KibbyError, Result};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KibbyPaths {
    pub home: PathBuf,
    pub config_root: PathBuf,
    pub state_root: PathBuf,
    pub data_root: PathBuf,
    pub hyprland_root: PathBuf,
    pub quickshell_root: PathBuf,
}

impl KibbyPaths {
    pub fn discover(config: &KibbyConfig) -> Result<Self> {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| KibbyError::Unsupported("HOME is not set".to_owned()))?;
        let config_home = env_path_or("XDG_CONFIG_HOME", &home.join(".config"));
        let state_home = env_path_or("XDG_STATE_HOME", &home.join(".local/state"));
        let data_home = env_path_or("XDG_DATA_HOME", &home.join(".local/share"));
        Self::from_roots(config, home, config_home, state_home, data_home)
    }

    /// Construct paths for an isolated HOME. This intentionally ignores the
    /// caller's XDG environment so tests and canaries cannot escape `home`.
    pub fn for_home(config: &KibbyConfig, home: PathBuf) -> Result<Self> {
        let config_home = home.join(".config");
        let state_home = home.join(".local/state");
        let data_home = home.join(".local/share");
        Self::from_roots(config, home, config_home, state_home, data_home)
    }

    fn from_roots(
        config: &KibbyConfig,
        home: PathBuf,
        config_home: PathBuf,
        state_home: PathBuf,
        data_home: PathBuf,
    ) -> Result<Self> {
        if !home.is_absolute() {
            return Err(KibbyError::Validation("HOME must be absolute".to_owned()));
        }
        Ok(Self {
            home: home.clone(),
            config_root: config_home.join("kibby"),
            state_root: state_home.join("kibby"),
            data_root: data_home.join("kibby"),
            hyprland_root: expand_home(&config.paths.hyprland, &home)?,
            quickshell_root: expand_home(&config.paths.quickshell, &home)?,
        })
    }

    pub fn config_file(&self) -> PathBuf {
        self.config_root.join("kibby.json")
    }

    pub fn lock_file(&self) -> PathBuf {
        self.config_root.join("kibby.lock.json")
    }

    pub fn transactions(&self) -> PathBuf {
        self.state_root.join("transactions")
    }
}

fn env_path_or(name: &str, fallback: &Path) -> PathBuf {
    env::var_os(name)
        .map(PathBuf::from)
        .unwrap_or_else(|| fallback.to_owned())
}

pub fn expand_home(value: &str, home: &Path) -> Result<PathBuf> {
    let path = if value == "~" {
        home.to_owned()
    } else if let Some(rest) = value.strip_prefix("~/") {
        home.join(rest)
    } else {
        PathBuf::from(value)
    };
    if !path.is_absolute()
        || path
            .components()
            .any(|item| matches!(item, std::path::Component::ParentDir))
    {
        return Err(KibbyError::Validation(format!(
            "path must be absolute (or start with ~/), without parent traversal: {value:?}"
        )));
    }
    Ok(path)
}
