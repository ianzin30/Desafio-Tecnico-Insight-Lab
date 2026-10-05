use url::Url;

use crate::CoreError;

/// Parses and validates a user-supplied homeserver address.
///
/// Only absolute `http`/`https` URLs are accepted. Bare server names such as
/// `matrix.org` are rejected: resolving them requires `.well-known` discovery,
/// which the core does not perform.
pub(crate) fn parse_homeserver_url(input: &str) -> Result<Url, CoreError> {
    let input = input.trim();
    let invalid = |reason: String| CoreError::InvalidHomeserver {
        url: input.to_owned(),
        reason,
    };

    let url = Url::parse(input).map_err(|err| invalid(err.to_string()))?;

    if !matches!(url.scheme(), "http" | "https") {
        return Err(invalid(format!(
            "unsupported scheme `{}`, expected `http` or `https`",
            url.scheme()
        )));
    }
    if url.host_str().is_none_or(str::is_empty) {
        return Err(invalid("missing host".to_owned()));
    }

    Ok(url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_http_and_https_urls() {
        for input in [
            "https://matrix.org",
            "  https://matrix-client.matrix.org/  ",
            "http://localhost:8008",
        ] {
            assert!(
                parse_homeserver_url(input).is_ok(),
                "{input} should be valid"
            );
        }
    }

    #[test]
    fn rejects_clearly_invalid_input() {
        for input in [
            "",
            "   ",
            "matrix.org",
            "not a url",
            "ftp://matrix.org",
            "https://",
        ] {
            let err = parse_homeserver_url(input).expect_err(input);
            assert!(
                matches!(err, CoreError::InvalidHomeserver { .. }),
                "{input}: unexpected error {err:?}"
            );
        }
    }
}
