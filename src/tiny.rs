use std::net::SocketAddr;

use hbb_common::{config, tokio};

pub const ADDRESS_ENV: &str = "RUSTDESK_TINY_ADDRESS";
pub const LISTEN_ENV: &str = "RUSTDESK_TINY_LISTEN";
pub const DIRECT_ONLY_ENV: &str = "RUSTDESK_TINY_DIRECT_ONLY";

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
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    hard.insert("disable-account".to_owned(), "Y".to_owned());
    hard.insert("disable-ab".to_owned(), "Y".to_owned());
    hard.insert("disable-group-panel".to_owned(), "Y".to_owned());
    drop(hard);

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
            return Err("--address requires an IP:port value".to_owned());
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
                .ok_or_else(|| format!("{arg} requires an IP:port value"))?;
            parse_address(address)?;
        }
        if matches!(arg.as_str(), "--relay" | "--play") {
            return Err(format!("{arg} is not available in RustDeskTiny"));
        }
    }
    Ok(())
}

pub fn parse_host_args(args: &[String]) -> Result<Option<SocketAddr>, String> {
    if args.first().map(String::as_str) != Some("host") {
        return Ok(None);
    }
    if args.len() != 3 || args[1] != "--listen" {
        return Err("usage: RustDeskTiny host --listen <IP:port>".to_owned());
    }
    parse_address(&args[2]).map(Some)
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

pub fn listen_address() -> Result<SocketAddr, String> {
    let value = std::env::var(LISTEN_ENV)
        .map_err(|_| "RustDeskTiny host listener requires an explicit IP:port".to_owned())?;
    parse_address(&value)
}

pub fn consume_listen(args: &mut Vec<String>) -> Result<(), String> {
    let positions: Vec<_> = args
        .iter()
        .enumerate()
        .filter_map(|(index, value)| (value == "--tiny-listen").then_some(index))
        .collect();
    if positions.is_empty() {
        return Ok(());
    }
    if positions.len() != 1 || positions[0] + 1 >= args.len() {
        return Err("--tiny-listen requires exactly one IP:port value".to_owned());
    }
    let index = positions[0];
    let address = parse_address(&args[index + 1])?;
    std::env::set_var(LISTEN_ENV, address.to_string());
    args.drain(index..=index + 1);
    Ok(())
}

#[hbb_common::tokio::main(flavor = "current_thread")]
pub async fn configure_service_host(address: SocketAddr) -> Result<(), String> {
    let mut stream = crate::ipc::connect_service(3000)
        .await
        .map_err(|error| format!("RustDesk service is unavailable: {error}"))?;
    stream
        .send(&crate::ipc::Data::TinyListen(address.to_string()))
        .await
        .map_err(|error| format!("failed to configure RustDesk service: {error}"))?;

    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    while tokio::time::Instant::now() < deadline {
        if tokio::time::timeout(
            std::time::Duration::from_millis(500),
            tokio::net::TcpStream::connect(address),
        )
        .await
        .is_ok_and(|result| result.is_ok())
        {
            return Ok(());
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    Err(format!(
        "RustDeskTiny service did not listen on {address} within 15 seconds"
    ))
}

pub fn parse_address(value: &str) -> Result<SocketAddr, String> {
    let address = value
        .trim()
        .parse::<SocketAddr>()
        .map_err(|_| format!("invalid IP:port address: {value}"))?;
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
