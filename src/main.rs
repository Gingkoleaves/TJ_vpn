use serde_json::{Value, json};
use std::{env, error::Error, fs, path::Path};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn read(path: &str) -> Result<String> {
    Ok(fs::read_to_string(path)?
        .trim_start_matches('\u{feff}')
        .to_owned())
}

fn identifier(value: &Value, key: &str) -> Result<String> {
    let text = value[key]
        .as_str()
        .ok_or_else(|| format!("Missing {key}"))?;
    if text.is_empty()
        || text.len() > 64
        || !text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    {
        return Err(format!("Invalid {key}").into());
    }
    Ok(text.into())
}

fn overlay_settings(config: &Value, state: &Value) -> Result<Value> {
    if state["connected"] != true {
        return Err("Native VPN state is not ready".into());
    }
    let name = identifier(config, "clashProxyName")?;
    let interface = identifier(config, "interfaceName")?;
    if state["interfaceName"] != interface {
        return Err("VPN state/interface mismatch".into());
    }
    let server = config["server"].as_str().ok_or("Missing server")?;
    let gateway = server
        .strip_prefix("https://")
        .ok_or("HTTPS server required")?
        .trim_end_matches('/')
        .split(':')
        .next()
        .ok_or("Missing gateway")?;
    if gateway.is_empty()
        || !gateway
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
    {
        return Err("Invalid gateway".into());
    }
    let mut rules = vec![
        format!("DOMAIN,{gateway},DIRECT"),
        "PROCESS-NAME,openconnect.exe,DIRECT".into(),
    ];
    let mut hosts = Vec::new();
    if let Some(values) = config.get("hosts") {
        for value in values.as_array().ok_or("hosts must be a list")? {
            let host = value
                .as_str()
                .ok_or("Invalid campus host")?
                .to_ascii_lowercase();
            if host.len() > 253
                || !host.contains('.')
                || host == gateway
                || host.split('.').any(|label| {
                    label.is_empty()
                        || label.len() > 63
                        || !label
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
                        || !label.as_bytes()[0].is_ascii_alphanumeric()
                        || !label.as_bytes()[label.len() - 1].is_ascii_alphanumeric()
                })
            {
                return Err("Invalid campus host or gateway loop".into());
            }
            rules.push(format!("DOMAIN,{host},{name}"));
            hosts.push(host);
        }
    }
    for prefix in state["addedRoutes"]
        .as_array()
        .ok_or("Missing addedRoutes")?
    {
        let prefix = prefix.as_str().ok_or("Invalid route")?;
        if prefix.ends_with("/0")
            || !prefix
                .bytes()
                .all(|b| b.is_ascii_digit() || b == b'.' || b == b'/')
        {
            return Err("Unsafe campus route".into());
        }
        rules.push(format!("IP-CIDR,{prefix},{name},no-resolve"));
    }
    for suffix in config["domainSuffixes"]
        .as_array()
        .ok_or("Missing domainSuffixes")?
    {
        let suffix = suffix.as_str().ok_or("Invalid domain suffix")?;
        if suffix.is_empty()
            || !suffix
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
        {
            return Err("Invalid campus suffix".into());
        }
        rules.push(format!("DOMAIN-SUFFIX,{suffix},{name}"));
    }
    let dns: Vec<String> = state["dns"]
        .as_array()
        .ok_or("Missing campus DNS")?
        .iter()
        .map(|ip| {
            let ip = ip.as_str().ok_or("Invalid DNS")?;
            ip.parse::<std::net::Ipv4Addr>()
                .map_err(|_| "Invalid campus DNS")?;
            Ok(format!("{ip}#{name}"))
        })
        .collect::<std::result::Result<_, &str>>()?;
    if dns.is_empty() {
        return Err("No campus DNS".into());
    }
    let mut resolved = serde_json::Map::new();
    if let Some(domains) = state["domains"].as_array() {
        for domain in domains {
            let host = domain["hostName"]
                .as_str()
                .ok_or("Invalid resolved domain")?;
            if !hosts.iter().any(|configured| configured == host) {
                continue;
            }
            let addresses = domain["addresses"]
                .as_array()
                .ok_or("Invalid resolved addresses")?;
            if addresses.is_empty() {
                continue;
            }
            for address in addresses {
                address
                    .as_str()
                    .ok_or("Invalid address")?
                    .parse::<std::net::Ipv4Addr>()?;
            }
            resolved.insert(host.to_owned(), json!(addresses));
        }
    }
    Ok(
        json!({"name":name, "interface":interface, "gateway":gateway, "rules":rules,
        "dns":dns, "suffixes":config["domainSuffixes"], "hosts":hosts, "resolved":resolved}),
    )
}

fn object<'a>(parent: &'a mut Value, key: &str) -> Result<&'a mut Value> {
    let parent_map = parent.as_object_mut().ok_or("Expected mapping")?;
    let value = parent_map.entry(key).or_insert_with(|| json!({}));
    if !value.is_object() {
        return Err(format!("{key} must be a mapping").into());
    }
    Ok(value)
}

fn overlay(source: &Value, settings: &Value) -> Result<Value> {
    let mut result = source.clone();
    if !result.is_object() {
        return Err("Mihomo root must be a mapping".into());
    }
    let name = settings["name"].as_str().ok_or("Missing name")?;
    let interface = settings["interface"].as_str().ok_or("Missing interface")?;
    let node = json!({"name":name, "type":"direct", "interface-name":interface, "udp":true, "ip-version":"ipv4"});
    let mut proxies = result
        .get("proxies")
        .cloned()
        .unwrap_or_else(|| json!([]))
        .as_array()
        .ok_or("proxies must be a list")?
        .clone();
    if let Some(existing) = proxies.iter_mut().find(|p| p["name"] == name) {
        if existing["type"] != "direct" || existing["interface-name"] != interface {
            return Err("Campus proxy name collides with an existing node".into());
        }
        *existing = node;
    } else {
        proxies.push(node);
    }
    result["proxies"] = json!(proxies);
    let old = result
        .get("rules")
        .cloned()
        .unwrap_or_else(|| json!([]))
        .as_array()
        .ok_or("rules must be a list")?
        .clone();
    let mut rules = settings["rules"].as_array().ok_or("Invalid rules")?.clone();
    rules.extend(
        old.into_iter()
            .filter(|rule| !settings["rules"].as_array().unwrap().contains(rule)),
    );
    result["rules"] = json!(rules);
    let dns = object(&mut result, "dns")?;
    let policy = object(dns, "nameserver-policy")?;
    for suffix in settings["suffixes"].as_array().ok_or("Invalid suffixes")? {
        policy[format!("+.{}", suffix.as_str().unwrap())] = settings["dns"].clone();
    }
    if let Some(hosts) = settings["hosts"].as_array() {
        for host in hosts {
            policy[host.as_str().ok_or("Invalid host")?] = settings["dns"].clone();
        }
    }
    // Gateway must remain independent of the tunnel it creates.
    policy[settings["gateway"].as_str().unwrap()] = json!(["223.5.5.5", "119.29.29.29"]);
    dns["direct-nameserver-follow-policy"] = json!(true);
    if let Some(resolved) = settings["resolved"]
        .as_object()
        .filter(|entries| !entries.is_empty())
    {
        dns["use-hosts"] = json!(true);
        let host_map = object(&mut result, "hosts")?;
        for (host, addresses) in resolved {
            host_map[host] = addresses.clone();
        }
    }
    // Do not change TUN flags, selected proxy groups, ports or fallback rules.
    Ok(result)
}

fn script(settings: &Value, base: &str) -> Result<String> {
    let encoded = serde_json::to_string(settings)?;
    Ok(format!(
        r#"// Generated by tongji-openconnect. Base script is preserved below.
const campusBaseMain = (function () {{
{base}
return (typeof main === 'function') ? main : (config => config);
}})();
const campusSettings = {encoded};
function main(config, profileName) {{
  config = campusBaseMain(config, profileName);
  const s = campusSettings;
  const node = {{name:s.name, type:'direct', 'interface-name':s.interface, udp:true, 'ip-version':'ipv4'}};
  const existing = (config.proxies || []).find(p => p.name === s.name);
  if (existing && (existing.type !== 'direct' || existing['interface-name'] !== s.interface))
    throw new Error('Campus proxy name collision');
  config.proxies = [...(config.proxies || []).filter(p => p.name !== s.name), node];
  config.rules = [...s.rules, ...(config.rules || []).filter(r => !s.rules.includes(r))];
  config.dns = config.dns || {{}};
  config.dns['nameserver-policy'] = config.dns['nameserver-policy'] || {{}};
  for (const suffix of s.suffixes) config.dns['nameserver-policy']['+.' + suffix] = s.dns;
  for (const host of (s.hosts || [])) config.dns['nameserver-policy'][host] = s.dns;
  config.dns['nameserver-policy'][s.gateway] = ['223.5.5.5', '119.29.29.29'];
  config.dns['direct-nameserver-follow-policy'] = true;
  if (Object.keys(s.resolved || {{}}).length) {{
    config.hosts = {{...(config.hosts || {{}}), ...s.resolved}};
    config.dns['use-hosts'] = true;
  }}
  return config;
}}
"#
    ))
}

fn run() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 6 || !["render", "script"].contains(&args[1].as_str()) {
        return Err(
            "Usage: campus-config <render|script> <source> <config.json> <state.json> <output>"
                .into(),
        );
    }
    if Path::new(&args[2]) == Path::new(&args[5]) {
        return Err("Output must differ from source".into());
    }
    let config: Value = serde_json::from_str(&read(&args[3])?)?;
    let state: Value = serde_json::from_str(&read(&args[4])?)?;
    let settings = overlay_settings(&config, &state)?;
    let output = if args[1] == "render" {
        let source: Value = serde_yaml_ng::from_str(&read(&args[2])?)?;
        serde_yaml_ng::to_string(&overlay(&source, &settings)?)?
    } else {
        script(&settings, &read(&args[2])?)?
    };
    fs::write(&args[5], output)?;
    println!("Campus configuration generated; existing external configuration retained.");
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn settings() -> Value {
        overlay_settings(
            &json!({"server":"https://vpn.tongji.cn", "clashProxyName":"Tongji-Native",
            "interfaceName":"TongjiVPN", "domainSuffixes":["tongji.edu.cn"]}),
            &json!({"connected":true,"interfaceName":"TongjiVPN", "addedRoutes":["192.0.2.10/32"],
            "dns":["202.120.190.208"]}),
        )
        .unwrap()
    }
    #[test]
    fn preserves_external_nodes_groups_tun_and_ports() {
        let input = json!({"proxies":[{"name":"External", "type":"vless", "password":"dummy"}],
            "proxy-groups":[{"name":"Select","type":"select","proxies":["External"]}],
            "rules":["MATCH,Select"],"tun":{"enable":true,"stack":"gvisor"},"mixed-port":7897});
        let output = overlay(&input, &settings()).unwrap();
        for key in ["proxy-groups", "tun", "mixed-port"] {
            assert_eq!(input[key], output[key]);
        }
        assert_eq!(input["proxies"][0], output["proxies"][0]);
        assert_eq!(
            output["rules"].as_array().unwrap().last().unwrap(),
            "MATCH,Select"
        );
    }
    #[test]
    fn overlay_is_idempotent() {
        let first = overlay(&json!({"rules":["MATCH,DIRECT"]}), &settings()).unwrap();
        assert_eq!(first, overlay(&first, &settings()).unwrap());
    }
    #[test]
    fn rejects_node_collision() {
        let input = json!({"proxies":[{"name":"Tongji-Native","type":"vless"}]});
        assert!(overlay(&input, &settings()).is_err());
    }
    #[test]
    fn requires_connected_matching_interface_and_rejects_default_routes() {
        let config = json!({"server":"https://vpn.tongji.cn","clashProxyName":"Tongji-Native",
            "interfaceName":"TongjiVPN","domainSuffixes":["tongji.edu.cn"]});
        for state in [
            json!({"connected":false}),
            json!({"connected":true,"interfaceName":"Wrong"}),
            json!({"connected":true,"interfaceName":"TongjiVPN","addedRoutes":["0.0.0.0/0"],"dns":["1.1.1.1"]}),
        ] {
            assert!(overlay_settings(&config, &state).is_err());
        }
    }
    #[test]
    fn campus_dns_bound_to_native_interface_and_gateway_independent() {
        let input =
            json!({"dns":{"nameserver-policy":{"+.google.com":"https://dns.google/dns-query"}}});
        let output = overlay(&input, &settings()).unwrap();
        assert_eq!(
            output["dns"]["nameserver-policy"]["+.google.com"],
            input["dns"]["nameserver-policy"]["+.google.com"]
        );
        assert_eq!(
            output["dns"]["nameserver-policy"]["+.tongji.edu.cn"][0],
            "202.120.190.208#Tongji-Native"
        );
        assert_eq!(output["rules"][0], "DOMAIN,vpn.tongji.cn,DIRECT");
    }
    #[test]
    fn explicit_domains_get_exact_rules_and_campus_dns_without_suffix_dependency() {
        let config = json!({"server":"https://vpn.tongji.cn","clashProxyName":"Tongji-Native",
            "interfaceName":"TongjiVPN","domainSuffixes":[],"hosts":["node.campus.example","node.department.internal"]});
        let state = json!({"connected":true,"interfaceName":"TongjiVPN","addedRoutes":["192.0.2.10/32"],"dns":["202.120.190.208"]});
        let settings = overlay_settings(&config, &state).unwrap();
        let output = overlay(&json!({"rules":["MATCH,DIRECT"]}), &settings).unwrap();
        assert!(
            output["rules"]
                .as_array()
                .unwrap()
                .contains(&json!("DOMAIN,node.campus.example,Tongji-Native"))
        );
        assert_eq!(
            output["dns"]["nameserver-policy"]["node.department.internal"][0],
            "202.120.190.208#Tongji-Native"
        );
        assert!(
            script(&settings, "function main(c) { return c; }")
                .unwrap()
                .contains("for (const host of (s.hosts || []))")
        );
        for host in [
            "bad.example,MATCH,DIRECT",
            "vpn.tongji.cn",
            "bad..tongji.cn",
        ] {
            let mut invalid = config.clone();
            invalid["hosts"] = json!([host]);
            assert!(overlay_settings(&invalid, &state).is_err());
        }
    }
    #[test]
    fn fallback_answers_are_pinned_and_unresolved_domains_do_not_abort_overlay() {
        let config = json!({"server":"https://vpn.tongji.cn","clashProxyName":"Tongji-Native",
            "interfaceName":"TongjiVPN","domainSuffixes":[],"hosts":["working.tongji.edu.cn","missing.tongji.edu.cn"]});
        let state = json!({"connected":true,"interfaceName":"TongjiVPN","addedRoutes":["192.0.2.10/32"],"dns":["202.120.190.208"],
            "domains":[{"hostName":"working.tongji.edu.cn","addresses":["192.0.2.10"],"dnsSource":"public"},
            {"hostName":"missing.tongji.edu.cn","addresses":[],"dnsSource":"unresolved"}]});
        let settings = overlay_settings(&config, &state).unwrap();
        let output = overlay(
            &json!({"hosts":{"external.example":"1.1.1.1"},"rules":["MATCH,DIRECT"]}),
            &settings,
        )
        .unwrap();
        assert_eq!(
            output["hosts"]["working.tongji.edu.cn"],
            json!(["192.0.2.10"])
        );
        assert_eq!(output["hosts"]["external.example"], "1.1.1.1");
        assert_eq!(output["dns"]["use-hosts"], true);
        assert!(output["hosts"].get("missing.tongji.edu.cn").is_none());
        assert!(script(&settings, "").unwrap().contains("...s.resolved"));
    }
}
