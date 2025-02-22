#!/bin/bash
#
#
# (c) 2018 Valentino Lauciani <valentino.lauciani@ingv.it>,
#          Matteo Quintiliani <matteo.quintiliani@ingv.it>,
#          Istituto Nazione di Geofisica e Vulcanologia.
# 
#####################################################

# Import config file
. $(dirname $0)/config.sh

### START - Check parameters ###
IN__STATIONXML_URL=
IN__TYPES=
while getopts :u:t: OPTION
do
	case ${OPTION} in
	u)	IN__STATIONXML_URL="${OPTARG}"
		;;
        t)	IN__TYPES="${OPTARG}"
		;;
        \?) echo "Invalid option: -$OPTARG" >/dev/null
		shift
		;;
        *)  #echo $OPTARG >/dev/null
		echo "Invalid OPTARG: -$OPTARG" >&2
		;;
	esac
done

# Check input parameter
if [[ -z ${IN__STATIONXML_URL} ]]; then
        echo ""
        echo " Please, set the STATIONXML_URL param"
        echo ""
        usage_entrypoint
        exit 1
fi 
if [[ -z ${IN__TYPES} ]]; then
	TYPES="resp"
else
	set -f   # disable wildcard expansion
	ARRAY_TYPES=(${IN__TYPES//[,]/ })
	set +f   # restore wildcard expansion

	for ((i=0; i<${#ARRAY_TYPES[@]}; i+=1))
	do
		if check_type ${ARRAY_TYPES[i]} ; then
                	echo "" > /dev/null
        	else
			echo ""
			echo " The \"${ARRAY_TYPES[i]}\" TYPE is not valid type."
			echo ""
        		exit 1		
        	fi
	done
fi

# Create dir
if [ ! -d ${DIR_LOG} ]; then
    mkdir -p ${DIR_LOG}
fi
if [ ! -d ${DIR_OUTPUT} ]; then
    mkdir -p ${DIR_OUTPUT}
fi
if [ ! -d ${DIR_TMP} ]; then
    mkdir -p ${DIR_TMP}
fi


# Check StationXML config file
if [ -f ${FILE_FDSNWS_NODES_URLS} ]; then
	echo "StationXML used to find NETWORK/STATION (update your \"${FILE_FDSNWS_NODES_URLS}\" file to add more)"
	cat ${FILE_FDSNWS_NODES_URLS}
else
	echo ""
	echo " Then file \"${FILE_FDSNWS_NODES_URLS}\" doesn't exist; check that it is mounted as a docker volume. View the help output."
	echo ""
	exit 1
fi
echo ""

# Parse input URL
STATIONXML_PARAMS=
STARTTIME="$( date +%Y-%m-%d )T00:00:00"
ENDTIME="$( date +%Y-%m-%d )T23:59:59"
NETWORK='*'
STATION='*'
CHANNEL='*'

set -f   # disable wildcard expansion
ARRAY_URL_TMP=(${IN__STATIONXML_URL//[=&]/ })
set +f   # restore wildcard expansion

for ((i=0; i<${#ARRAY_URL_TMP[@]}; i+=2))
do
	if [[ "${ARRAY_URL_TMP[i]}" == "level" ]] || [[ "${ARRAY_URL_TMP[i]}" == "format" ]]; then
		echo "" > /dev/null
	else
		STATIONXML_PARAMS="${STATIONXML_PARAMS}${ARRAY_URL_TMP[i]}=${ARRAY_URL_TMP[i+1]}&"
	fi
done
STATIONXML_PARAMS=${STATIONXML_PARAMS%?}

# 
STATIONXML_PARAMS_FIND="level=station&format=text&${STATIONXML_PARAMS}"

# Search StationXML that match IN__STATIONXML_URL
EXISTS=0
while read FDSNWS_NODE_URL; do
    STATIONXML_FULL_URL="${FDSNWS_NODE_URL}/fdsnws/station/1/query?${STATIONXML_PARAMS_FIND}"
    echo "Searching on \"${STATIONXML_FULL_URL}\""
    curl "${STATIONXML_FULL_URL}" -o "${FILE_CURL1}" --max-time 20 --write-out "%{http_code}\\n" > ${FILE_CURL1_HTTPCODE} -s -S
    RETURNED_CODE=${?}

    HTTP_CODE=$( cat ${FILE_CURL1_HTTPCODE} )
    if (( ${RETURNED_CODE} == 0 )) && (( ${HTTP_CODE} == 200 )); then
        N_STATIONS=$( grep -v ^"#" ${FILE_CURL1} | wc | awk '{print $1}' )
        echo " ${N_STATIONS} station(s) found!"
        EXISTS=1

        # get node host (ie: rtserve.beg.utexas.edu, eida.ipgp.fr, webservices.ingv.it, ...)
        FDSNWS_NODE=${FDSNWS_NODE_URL#*//} #removes stuff upto // from begining
        FDSNWS_NODE=${FDSNWS_NODE%/*} #removes stuff from / all the way to end

        # set full path
        FDSNWS_NODE_PATH=${DIR_TMP}/${FDSNWS_NODE}

        # create dir
        if [ ! -d ${FDSNWS_NODE_PATH} ]; then
            mkdir -p ${FDSNWS_NODE_PATH}
        fi

        # create 'stationxml_station.txt' file with the name of fdsnws node
        echo ${STATIONXML_FULL_URL} > ${FDSNWS_NODE_PATH}/stationxml_station.txt

        # Remove comment line from StationXML 'text' output
        grep -v ^# ${FILE_CURL1} > ${FILE_CURL1}.new
        mv ${FILE_CURL1}.new ${FILE_CURL1}

        # Get only NETWORK and STATION, Sort and Unique
        cat ${FILE_CURL1} | awk -F"|" '{print $1"|"$2}' | sort -u > ${FILE_CURL1}.new
        mv ${FILE_CURL1}.new ${FILE_CURL1}

        # create 'net_sta.txt' file with only NET and STA for that node
        cp ${FILE_CURL1} ${FDSNWS_NODE_PATH}/net_sta.txt
    fi
done < ${FILE_FDSNWS_NODES_URLS}
echo ""

if (( ${EXISTS} == 1 )); then
	for ((i=0; i<${#ARRAY_TYPES[@]}; i+=1))
        do
		TYPE=${ARRAY_TYPES[i]}
    		#if [[ "${TYPE}" == "resp" ]] || [[ "${TYPE}" == "dless" ]]; then
        	#	${DIR_WORK}/02_get_dless-resp-paz.sh -t ${TYPE}
    		#elif [[ "${TYPE}" == "sac" ]] || [[ "${TYPE}" == "dless_and_miniseed" ]]; then
        	#	${DIR_WORK}/02_get_dless-resp-paz.sh -t ${TYPE}
        	#	${DIR_WORK}/03_get_dataselect_list-mseed-sac.sh -t ${TYPE}
    		#elif [[ "${TYPE}" == "dataselect_list" ]] || [[ "${TYPE}" == "miniseed" ]]; then
        	#	${DIR_WORK}/03_get_dataselect_list-mseed-sac.sh -t ${TYPE}
    		#fi

                if [[ "${TYPE}" == "resp" ]] || [[ "${TYPE}" == "dless" ]] || [[ "${TYPE}" == "paz" ]]; then
                        ${DIR_WORK}/02_get_dless-resp-paz.sh -t ${TYPE}
		fi
                if [[ "${TYPE}" == "dataselect_list" ]] || [[ "${TYPE}" == "miniseed" ]] || [[ "${TYPE}" == "sac" ]]; then
                        ${DIR_WORK}/03_get_dataselect_list-mseed-sac.sh -t ${TYPE}
                fi
    	done
else 
	echo ""
    	echo "There are no FDSNWS_NODE_URL that contains \"${STATIONXML_PARAMS}\"."
    	echo ""
    	exit -1
fi

#
for FDSNWS_NODE_PATH in $( ls -d ${DIR_TMP}/* ); do
        DIR_OUTPUT_NODE=${DIR_OUTPUT}/$( basename ${FDSNWS_NODE_PATH} )
        mkdir -p ${DIR_OUTPUT_NODE}

        for ((i=0; i<${#ARRAY_TYPES[@]}; i+=1))
        do
                TYPE=${ARRAY_TYPES[i]}
                cp -R ${FDSNWS_NODE_PATH}/${TYPE} ${DIR_OUTPUT_NODE}
        done
done
echo ""
echo "OUTPUT=./OUTPUT/${DATE_NOW}"
echo ""

# Remove temporary files/directories
#if [ -d ${DIR_TMP} ]; then
#    rm -fr ${DIR_TMP}
#fi
