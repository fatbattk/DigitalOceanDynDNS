# Digital Ocean Dynamic DNS Updater

Simple **Bash** script to automatically add/update Digital Ocean DNS record for a domain. Includes basic error checking and common linux commands only, except for [`jq`](https://stedolan.github.io/jq/) which is designed to be easy to install.

My use case: *Connect to home server that is on a dynamic IP via a fixed domain (ala DynDNS).*
`(e.g.- nas.mydomain.com vs. 74.125.231.100)`

## Usage

1. Generate [Personal Access Token](https://cloud.digitalocean.com/settings/applications) from your Digital Ocean account.

2. Modify the script to add `access token` and set script permission to `755`.

		chmod 755 /path/to/file/do_dns_update.sh

3. [Cron](http://en.wikipedia.org/wiki/Cron#Predefined_scheduling_definitions) the script to update Digital Ocean's DNS at desired frequency. (Note: *API rate limit is currently 1200 /hr. Script run uses 2.*)

		# once every two days @ 7:30am.
		30 07 */2 * * /path/to/file/do_dns_update.sh -s nas mydomain.com

## Options

	$ ./do_dns_update.sh -h

	Usage: do_dns_update.sh [options...] <record name> <domain>
	Options:
	  -h      This help text
	  -u      Updates only. Don't add non-existing
	  -s      Silent mode. Don't output anything


## Requires

* [Domain](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-host-name-with-digitalocean) added on Digital Ocean.
* Crontab or equivalent.
* Available linux commands: **awk, curl, grep, mktemp, sed, tr**

## Adapted From

[PHP / Python version](https://github.com/bensquire/Digital-Ocean-Dynamic-DNS-Updater)

## License

The MIT License (MIT).
