use std::net::SocketAddr;

use hbb_common::{config, password_security};

pub const ADDRESS_ENV: &str = "RUSTDESK_TINY_ADDRESS";
pub const DIRECT_ONLY_ENV: &str = "RUSTDESK_TINY_DIRECT_ONLY";
const TEMPORARY_PASSWORD_OPTION: &str = "tiny-temporary-password";

const CONNECTION_COMMANDS: &[&str] = &[
    "--connect",
    "--file-transfer",
    "--view-camera",
    "--port-forward",
    "--terminal",
    "--rdp",
];

pub fn initialize() {
    std::env::set_var(DIRECT_ONLY_ENV, "1");
    *config::APP_NAME.write().unwrap() = "RustDeskTiny".to_owned();
    initialize_temporary_password();
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    hard.insert("rustdesk-tiny".to_owned(), "Y".to_owned());
    hard.insert("disable-account".to_owned(), "Y".to_owned());
    hard.insert("disable-ab".to_owned(), "Y".to_owned());
    hard.insert("disable-group-panel".to_owned(), "Y".to_owned());
    drop(hard);

    config::OVERWRITE_SETTINGS
        .write()
        .unwrap()
        .insert("direct-server".to_owned(), "Y".to_owned());

    let mut builtin = config::BUILTIN_SETTINGS.write().unwrap();
    for key in [
        "hide-network-settings",
        "hide-server-settings",
        "hide-proxy-settings",
        "hide-websocket-settings",
    ] {
        builtin.insert(key.to_owned(), "Y".to_owned());
    }
}

fn initialize_temporary_password() {
    let configured = config::Config::get_option(TEMPORARY_PASSWORD_OPTION);
    let required_length = password_security::temporary_password_length();
    let password = if configured.chars().count() == required_length {
        configured
    } else {
        let generated = config::Config::get_auto_password(required_length);
        config::Config::set_option(TEMPORARY_PASSWORD_OPTION.to_owned(), generated.clone());
        generated
    };
    *password_security::TEMPORARY_PASSWORD.write().unwrap() = password;
}

pub fn update_temporary_password() {
    let password =
        config::Config::get_auto_password(password_security::temporary_password_length());
    config::Config::set_option(TEMPORARY_PASSWORD_OPTION.to_owned(), password.clone());
    *password_security::TEMPORARY_PASSWORD.write().unwrap() = password;
}

pub fn consume_address(args: &mut Vec<String>) -> Result<Option<String>, String> {
    let mut value = None;
    let mut index = 0;
    while index < args.len() {
        if args[index] != "--address" {
            index += 1;
            continue;
        }
        if value.is_some() {
            return Err("--address may only be specified once".to_owned());
        }
        if index + 1 >= args.len() {
            return Err("--address requires an ip:port value".to_owned());
        }
        value = Some(parse_address(&args[index + 1])?.to_string());
        args.drain(index..=index + 1);
    }
    if value.is_none() {
        if let Ok(address) = std::env::var(ADDRESS_ENV) {
            if !address.trim().is_empty() {
                value = Some(parse_address(&address)?.to_string());
            }
        }
    }
    if let Some(address) = value.as_deref() {
        std::env::set_var(ADDRESS_ENV, address);
    }
    Ok(value)
}

pub fn validate_connection_args(args: &[String]) -> Result<(), String> {
    for (index, arg) in args.iter().enumerate() {
        if CONNECTION_COMMANDS.contains(&arg.as_str()) {
            let address = args
                .get(index + 1)
                .ok_or_else(|| format!("{arg} requires an ip:port value"))?;
            parse_address(address)?;
        }
        if matches!(arg.as_str(), "--relay" | "--play") {
            return Err(format!("{arg} is not available in RustDeskTiny"));
        }
    }
    Ok(())
}

#[cfg(windows)]
pub fn handle_service_command(args: &[String]) -> Option<Result<(), String>> {
    let command = args.first().map(String::as_str)?;
    match command {
        "--ensure-service" if args.len() == 1 => Some(ensure_embedded_service()),
        "--service-start-type" if args.len() == 2 => {
            let value = match args[1].as_str() {
                "auto" => "auto",
                "demand" => "demand",
                _ => return Some(Err("service start type must be auto or demand".to_owned())),
            };
            Some(run_sc(&["config", &crate::get_app_name(), "start=", value]))
        }
        "--start-service" if args.len() == 1 => Some(run_sc(&["start", &crate::get_app_name()])),
        "--stop-service" if args.len() == 1 => Some(run_sc(&["stop", &crate::get_app_name()])),
        _ => None,
    }
}

#[cfg(windows)]
fn ensure_embedded_service() -> Result<(), String> {
    let service_name = crate::get_app_name();
    if std::process::Command::new("sc.exe")
        .args(["query", service_name.as_str()])
        .status()
        .map_err(|error| format!("failed to query {service_name} service: {error}"))?
        .success()
    {
        return Ok(());
    }

    let executable = std::env::current_exe()
        .map_err(|error| format!("failed to resolve embedded service executable: {error}"))?;
    let bin_path = format!("\"{}\" --service", executable.display());
    run_sc(&[
        "create",
        service_name.as_str(),
        "binPath=",
        bin_path.as_str(),
        "start=",
        "demand",
        "DisplayName=",
        "RustDeskTiny Service",
    ])?;

    run_sc(&["query", service_name.as_str()])
}

#[cfg(windows)]
fn run_sc(args: &[&str]) -> Result<(), String> {
    let status = std::process::Command::new("sc.exe")
        .args(args)
        .status()
        .map_err(|error| format!("failed to run sc.exe: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("sc.exe exited with {status}"))
    }
}

pub fn parse_address(value: &str) -> Result<SocketAddr, String> {
    let address = value
        .trim()
        .parse::<SocketAddr>()
        .map_err(|_| format!("invalid ip:port address: {value}"))?;
    if address.ip().is_unspecified() || address.port() == 0 {
        return Err(format!(
            "wildcard and zero-port addresses are not allowed: {value}"
        ));
    }
    Ok(address)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_ip_with_nonzero_port() {
        assert!(parse_address("10.10.100.75:39090").is_ok());
        assert!(parse_address("[fd00::75]:39090").is_ok());
    }

    #[test]
    fn rejects_ids_domains_wildcards_and_missing_ports() {
        for value in [
            "123456789",
            "example.com:39090",
            "10.10.100.75",
            "0.0.0.0:39090",
            "[::]:39090",
            "127.0.0.1:0",
        ] {
            assert!(parse_address(value).is_err(), "accepted {value}");
        }
    }

    #[test]
    fn rejects_relay_and_legacy_play() {
        assert!(validate_connection_args(&["--relay".to_owned()]).is_err());
        assert!(validate_connection_args(&["--play".to_owned(), "a".to_owned()]).is_err());
    }
}
