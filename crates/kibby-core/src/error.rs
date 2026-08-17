use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum KibbyError {
    #[error("I/O error at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("invalid JSON at {path}: {source}")]
    Json {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("unsupported configuration: {0}")]
    Unsupported(String),
    #[error("validation failed: {0}")]
    Validation(String),
    #[error("external command failed: {0}")]
    Command(String),
    #[error("nothing is available to recover")]
    NothingToRecover,
}

pub type Result<T> = std::result::Result<T, KibbyError>;

pub(crate) fn io_error(path: impl Into<PathBuf>, source: std::io::Error) -> KibbyError {
    KibbyError::Io {
        path: path.into(),
        source,
    }
}
