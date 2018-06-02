#!/bin/bash
# @requires jq, curl, grep, mktemp, sed, tr.

## START EDIT HERE.
do_access_token="";  # paste your DO Personal Access Token here.
curl_timeout="15";
loop_max_records="50";
url_do_api="https://api.digitalocean.com/v2";
url_ext_ip="http://checkip.dyndns.org";
url_ext_ip2="http://ifconfig.me/ip";
update_only=false;
verbose=true;
filename="$(basename $BASH_SOURCE)";
## END EDIT.

# get options.
while getopts "ush" opt; do
  case $opt in
    u)  # update.
      update_only=true;
      ;;
    s)  # silent.
      verbose=false;
      ;;
    h)  # help.
      echo "Usage: $filename [options...] <record name> <domain>";
      echo "Options:";
      echo "  -h      This help text";
      echo "  -u      Updates only. Don't add non-existing";
      echo "  -s      Silent mode. Don't output anything";
      echo "Example:";
      echo "  Add/Update nas.mydomain.com DNS A record with current public IP";
      echo "    ./$filename -s nas mydomain.com";
      echo;
      exit 0;
      ;;
    \?)
      echo "Invalid option: -$OPTARG (See -h for help)" >&2
      exit 1;
      ;;
  esac
done

# validate.
shift $(( OPTIND - 1 ));
do_record="$1";
do_domain="$2";
if [ $# -lt 2 ] || [ -z "$do_record" ] || [ -z "$do_domain" ] ; then
  echo "Missing required arguments. (See -h for help)";
  exit 1;
elif [ -z "$do_access_token" ] ; then
  echo "Missing token. Please edit this script and add your access token first.";
  exit 1;
fi

echov()
{
  if [ $verbose == true ] ; then
    if [ $# == 1 ] ; then
      echo "$1";
    else
      printf "$@";
    fi
  fi
}

get_external_ip()
{
  ip_address="$(curl -s --connect-timeout $curl_timeout $url_ext_ip | sed -e 's/.*Current IP Address: //' -e 's/<.*$//' | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')";
  if [ -z "$ip_address" ] ; then
    ip_address="$(curl -s --connect-timeout $curl_timeout $url_ext_ip2 | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')";
    if [ -z "$ip_address" ] ; then
      return 1;
    fi
  else
    return 0;
  fi
}

# https://developers.digitalocean.com/#list-all-domain-records
get_record()
{
  next_page="$url_do_api/domains/$do_domain/records"

  while [ ! -z $next_page ]; do
    local tmpfile="$(mktemp)";
    curl -s --connect-timeout "$curl_timeout" -H "Authorization: Bearer $do_access_token" -X GET "$next_page" > "$tmpfile"
    if [ ! -s "$tmpfile" ] ; then
      return 1;
    fi

    # "// empty" makes jq output "" instead of "null" when we get to the end of the list,
    # and -r makes it output strings as shell strings instead of wrapped in quotes as json
    # which makes it fit in better with shell. See https://github.com/sftedolan/jq/issues/354
    next_page="$(jq -r ".links.pages.next // empty" < $tmpfile)";

    # XXX pre-counting the loop is probably unecessary; we should be able to get
    # jq to give us items in a single pass; probably even to do most of the logic internally,
    # which would parse faster.
    local do_num_records="$(jq ".meta.total" < $tmpfile)";
    if [[ ! "$do_num_records" =~ ^[0-9]+$ ]] || [ "$do_num_records" -gt "$loop_max_records" ] ; then
      do_num_records=$loop_max_records;
    fi

    for i in `seq 1 $do_num_records`
    do
      record['name']="$(jq -r ".domain_records[$i].name // empty" < $tmpfile)";
      if [ "${record[name]}" == "$do_record" ] ; then
        record['id']="$(jq -r ".domain_records[$i].id // empty" < $tmpfile)";
        record['data']="$(jq -r ".domain_records[$i].data // empty" < $tmpfile)";

        if [ ! -z "${record[id]}" ] && [[ "${record[id]}" =~ ^[0-9]+$ ]] ; then
          rm -f "$tmpfile";
          return 0;
        fi
        break;
      fi
    done

    rm -f "$tmpfile";
  done

  return 1;
}

# https://developers.digitalocean.com/#update-a-domain-record
set_record_ip()
{
  local id=$1
  local ip=$2

  local data=`curl -s --connect-timeout $curl_timeout -H "Content-Type: application/json" -H "Authorization: Bearer $do_access_token" -X PUT "$url_do_api/domains/$do_domain/records/$id" -d'{"data":"'"$ip"'"}'`;
  if [ -z "$data" ] || [[ "$data" != *"id\":$id"* ]]; then
    return 1;
  else
    return 0;
  fi
}

# https://developers.digitalocean.com/v2/#create-a-new-domain-record
new_record()
{
  local ip=$1

  local data=`curl -s --connect-timeout $curl_timeout -H "Content-Type: application/json" -H "Authorization: Bearer $do_access_token" -X POST "$url_do_api/domains/$do_domain/records" -d'{"name":"'"$do_record"'","data":"'"$ip"'","type":"A"}'`;
  if [ -z "$data" ] || [[ "$data" != *"data\":\"$ip"* ]]; then
    return 1;
  else
    return 0;
  fi
}

# start.
echov "* Updating %s.%s: $(date +"%Y-%m-%d %H:%M:%S")\n\n" "$do_record" "$do_domain";

echov "* Fetching external IP from: $url_ext_ip";
get_external_ip;
if [ $? -ne 0 ] ; then
  echov "Unable to extract external IP address";
  exit 1;
fi

echov "* Fetching Record ID for: $do_record";
just_added=false;
declare -A record;
get_record;
if [ $? -ne 0 ] ; then
  if [ $update_only == true ] ; then
    echov "Unable to find requested record in DO account";
    exit 1;
  else
    echov "* No record found. Adding: $do_record";
    new_record "$ip_address";
    if [ $? -ne 0 ] ; then
      echov "Unable to add new record";
      exit 1;
    fi
    just_added=true;
  fi
fi

if [ $update_only == true ] || [ $just_added != true ] ; then
  echov "* Comparing ${record[data]} to $ip_address";
  if [ "${record[data]}" == "$ip_address" ] ; then
    echov "Record $do_record.$do_domain already set to $ip_address";
    exit 1;
  fi

  echov "* Updating record ${record[name]}.$do_domain to $ip_address";
  set_record_ip "${record[id]}" "$ip_address";
  if [ $? -ne 0 ] ; then
    echov "Unable to update IP address";
    exit 1;
  fi
fi

echov "\n* IP Address successfully added/updated.\n\n" "";
exit 0;
