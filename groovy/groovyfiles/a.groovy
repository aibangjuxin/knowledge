
// ...existing code...
String fqdn = fqdns.join(" ")
def extraArgs = ((env ==~ /^[a-zA-Z]+\d+$/) && (saasCode?.equalsIgnoreCase("micro") || saasCode?.equalsIgnoreCase("dynamic"))) ? "-m blue-coat" : ""
def shellCommand = """ y|sh squid_proxy_install.sh -e ${env}-${region} -c ${saasCode} -f "${fqdn}" ${extraArgs}
"""
// ...existing code...