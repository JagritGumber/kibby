mod assets;
mod config;
mod error;
mod foundation;
mod paths;
mod probe;
mod transaction;

pub use config::{FoundationOptions, KibbyConfig, PathsConfig, Providers};
pub use error::{KibbyError, Result};
pub use foundation::{Adapter, FoundationPlan, HyprlandDialect, build_foundation_plan};
pub use paths::KibbyPaths;
pub use probe::{CommandRunner, HostProbe, Probe, ProcessResult, Runner};
pub use transaction::{
    ApplyResult, DoctorReport, RecoveryResult, apply_foundation, doctor, recover_latest,
};
