#!/bin/bash
# @requires awk, curl, grep, mktemp, sed, tr.

## START EDIT HERE.
do_record="";
do_domain="";
do_access_token="";
curl_timeout="15";
loop_max_records="50";
url_do_api="https://api.digitalocean.com/v2";
url_ext_ip="http://checkip.dyndns.org";
url_ext_ip2="http://ifconfig.me/ip";
## END EDIT.

# modified from https://gist.github.com/cjus/1047794#comment-1249451
json_value()
{
  local KEY=$1
  local num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/\042'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
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
  local tmpfile="$(mktemp)";
  curl -s --connect-timeout "$curl_timeout" -H "Authorization: Bearer $do_access_token" -X GET "$url_do_api/domains/$do_domain/records" > "$tmpfile"
  if [ ! -s "$tmpfile" ] ; then
    return 1;
  fi

  local do_num_records="$(json_value total 1 < $tmpfile)";
  if [[ ! "$do_num_records" =~ ^[0-9]+$ ]] || [ "$do_num_records" -gt "$loop_max_records" ] ; then
    do_num_records=$loop_max_records;
  fi

  for (( i=1; i<="$do_num_records"; i++ ))
  do
    record['name']="$(json_value name $i < $tmpfile)";
    if [ "${record[name]}" == "$do_record" ] ; then
      record['id']="$(json_value id $i < $tmpfile)";
      record['data']="$(json_value data $i < $tmpfile)";

      if [ ! -z "${record[id]}" ] && [[ "${record[id]}" =~ ^[0-9]+$ ]] ; then
        rm -f "$tmpfile";
        return 0;
      fi
      break;
    fi
  done

  rm -f "$tmpfile";
  return 1;
}

# https://developers.digitalocean.com/#update-a-domain-record
set_record_ip()
{
  local id=$1
  local ip=$2

  local data=`curl -s /dev/stdout --connect-timeout $curl_timeout -H "Content-Type: application/json" -H "Authorization: Bearer $do_access_token" -X PUT "$url_do_api/domains/$do_domain/records/$id" -d'{"data":"'"$ip"'"}'`;
  if [ -z "$data" ] || [[ "$data" != *"id\":$id"* ]]; then
    return 1;
  else
    return 0;
  fi
}

# start.
printf "* Updating %s.%s: $(date +"%Y-%m-%d %H:%M:%S")\n\n" "$do_record" "$do_domain";

echo "* Fetching external IP from: $url_ext_ip";
get_external_ip;
if [ $? -ne 0 ] ; then
  echo "Unable to extract external IP address";
  exit 1;
fi

echo "* Fetching Record ID for: $do_record";
declare -A record;
get_record;
if [ $? -ne 0 ] ; then
  echo "Unable to find requested record in DO account";
  exit 1;
fi

echo "* Comparing ${record[data]} to $ip_address";
if [ "${record[data]}" == "$ip_address" ] ; then
  echo "Record $do_record.$do_domain already set to $ip_address";
  exit 1;
fi

echo "* Updating record ${record[name]}.$do_domain to $ip_address";
set_record_ip "${record[id]}" "$ip_address";
if [ $? -ne 0 ] ; then
  echo 'Unable to update IP address';
  exit 1;
fi

printf "\n* IP Address successfully updated.\n\n";
exit 0
