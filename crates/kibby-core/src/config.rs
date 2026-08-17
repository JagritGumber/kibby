use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::error::{KibbyError, Result, io_error};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct KibbyConfig {
    #[serde(rename = "$schema", default = "default_schema")]
    pub schema: String,
    pub schema_version: u32,
    pub adapter: String,
    pub paths: PathsConfig,
    pub providers: Providers,
    pub foundation: FoundationOptions,
    #[serde(default)]
    pub components: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PathsConfig {
    pub hyprland: String,
    pub quickshell: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Providers {
    pub terminal: String,
    pub launcher: String,
    pub lock: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FoundationOptions {
    pub uwsm: String,
    pub volume_step: u8,
    pub brightness_step: u8,
}

fn default_schema() -> String {
    "https://kibby.dev/schema/config-v1.json".to_owned()
}

impl Default for KibbyConfig {
    fn default() -> Self {
        Self {
            schema: default_schema(),
            schema_version: 1,
            adapter: "auto".to_owned(),
            paths: PathsConfig {
                hyprland: "~/.config/hypr".to_owned(),
                quickshell: "~/.config/quickshell/kibby".to_owned(),
            },
            providers: Providers {
                terminal: "kitty".to_owned(),
                launcher: "fuzzel".to_owned(),
                lock: "hyprlock".to_owned(),
            },
            foundation: FoundationOptions {
                uwsm: "auto".to_owned(),
                volume_step: 5,
                brightness_step: 5,
            },
            components: Vec::new(),
        }
    }
}

impl KibbyConfig {
    pub fn load(path: &Path) -> Result<Self> {
        let text = fs::read_to_string(path).map_err(|error| io_error(path, error))?;
        let value: Self = serde_json::from_str(&text).map_err(|source| KibbyError::Json {
            path: path.to_owned(),
            source,
        })?;
        value.validate()?;
        Ok(value)
    }

    pub fn validate(&self) -> Result<()> {
        if self.schema_version != 1 {
            return Err(KibbyError::Validation(format!(
                "unsupported config schema version {}",
                self.schema_version
            )));
        }
        if !matches!(
            self.adapter.as_str(),
            "auto" | "arch" | "cachyos" | "generic"
        ) {
            return Err(KibbyError::Validation(format!(
                "unknown adapter {:?}",
                self.adapter
            )));
        }
        if !matches!(self.foundation.uwsm.as_str(), "auto" | "always" | "never") {
            return Err(KibbyError::Validation(
                "foundation.uwsm must be auto, always, or never".to_owned(),
            ));
        }
        if !(1..=20).contains(&self.foundation.volume_step)
            || !(1..=20).contains(&self.foundation.brightness_step)
        {
            return Err(KibbyError::Validation(
                "volumeStep and brightnessStep must be between 1 and 20".to_owned(),
            ));
        }
        for (kind, provider, allowed) in [
            ("terminal", self.providers.terminal.as_str(), &["kitty"][..]),
            (
                "launcher",
                self.providers.launcher.as_str(),
                &["fuzzel"][..],
            ),
            ("lock", self.providers.lock.as_str(), &["hyprlock"][..]),
        ] {
            if !allowed.contains(&provider) {
                return Err(KibbyError::Validation(format!(
                    "unsupported {kind} provider {provider:?} in schema v1"
                )));
            }
        }
        Ok(())
    }

    pub fn pretty_json(&self) -> Result<String> {
        let mut text = serde_json::to_string_pretty(self).map_err(|source| KibbyError::Json {
            path: Path::new("<generated config>").to_owned(),
            source,
        })?;
        text.push('\n');
        Ok(text)
    }
}
