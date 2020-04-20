#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Script		: wlup.sh
# Descrição		: << descrição breve de sua funcionalidade >>
# Versão		: 0.1-beta
# Autor			: Eppur Si Muove
# Contato		: eppur.si.muove@keemail.me
# Criação		: 11/04/2020
# Modificação	:
# Licença		: GNU/GPL v3.0
# -------------------------------------------------------------------------
# Uso:
#
# -------------------------------------------------------------------------

# -------------| CONSTANTES GLOBAIS |------------------------------------
declare -r IF_CONF_FILE="/etc/network/interfaces"
declare -r IF_CONF_DIR="/etc/network/interfaces.d"
declare -r WPA_CONF_DIR="/etc/wpa_supplicant"

# -------------| VARIÁVEIS GLOBAIS |-------------------------------------
# Predefinições por interface com as redes separadas por dois pontos.
# Ex.: PREDEFINICOES[wlan0]="my_net:other net:another_net"
declare -a PREDEFINICOES
declare -a INTERFACES
declare -a REDES
declare -a DEFS
COLS=$(tput cols)
INTERFACE=''
REDE=''


checa_dirs(){
	# Cria subdiretórios, caso ainda não existam
	[[ ! -d $IF_CONF_DIR ]] && mkdir -p $IF_CONF_DIR && [[ $? -ne 0 ]] && return 1
	[[ ! -d $WPA_CONF_DIR ]] && mkdir -p $WPA_CONF_DIR && [[ $? -ne 0 ]] && return 1

	# /etc/network/interfaces carrega arquivos do subdiretório interfaces.d ?
	local lineSource=$(grep "source $IF_CONF_DIR/*" $IF_CONF_FILE)
	if [[ "$lineSource" != "source $IF_CONF_DIR/*" ]]; then
		sed -i "1i\source $IF_CONF_DIR/*" $IF_CONF_FILE
		[[ $? -ne 0 ]] && return 1
	fi
	return 0
}

# --------| ESCREVE CABEÇALHO DE SEÇÃO |------------------------------------
escr_secao(){
	clear
	local secao=" | $1 | "
	local cols=$(($COLS - $(tr -d "\n" <<< $secao | wc -m) ))
	local i=1
	while [[ $i -le $COLS ]]; do
		echo -n "="
		i=$((i+1))
	done
	i=1
	while [[ $i -le $((cols/2)) ]]; do
		echo -n "-"
		i=$((i+1))
	done
	echo -n "$secao"
	i=1
	while [[ $i -le $((cols/2)) ]]; do
		echo -n "-"
		i=$((i+1))
	done
	i=1
	while [[ $i -le $COLS ]]; do
		echo -n "="
		i=$((i+1))
	done
}

# --------| ESCREVE CABEÇALHO DE SUBSEÇÃO |------------------------------------
escr_subsecao(){
	local i=1
	local subsecao="\n\n »»»» | $1 | "
	echo -e -n "$subsecao"
	local restante=$(($COLS - $(tr -d "\n" <<< $subsecao | wc -m) ))
	while [[ $i -le $restante ]]; do
		echo -n "·"
		i=$((i+1))
	done
}

# -------| LISTA OS ITENS DE UMA SUBSEÇÃO OU SEÇÃO |----------------------------
escr_item(){
	local item=" »»»» |→→→ $1"
	echo -ne "\n$item"
}

# -------| POPULA A ARRAY ''INTERFACES'' COM AS QUE FOREM ENCONTRADAS |-----------
obtem_interfaces(){
	# ---------| Reseta array INTERFACES |-------------------------------
	INTERFACES=()

	# ---------| Obtém as interfaces de rede sem-fio cujos nomes começam com wl
	local tempNics=$(ip addr show | grep ": wl" | cut -d" " -f2 | tr -d :)

	# ---------| Sai se não houver interfaces de rede sem-fio |----------
	[[ -z $tempNics ]] && return 1

	# ---------| Armazena cada interface num elemento da array ''INTERFACES''
	local i=-1
	for tempNic in $tempNics; do
		INTERFACES[$((++i))]=$tempNic
	done
	return 0
}

# ------| POPULA A ARRAY ''REDES'' COM AS QUE FOREM ESCANEADAS PELA INTERFACE $1
obtem_redes(){
	# --------| Reset array REDES |--------------------------------------
	REDES=()

	# --------| Obtém as redes disponíveis para a interface selecionada $1
	tempRedes=$(iw dev ${INTERFACES[$1]} scan -u | grep -i ssid | sed s/" * "/" "/ | cut -d" " -f2)

	# --------| Sai se não houver redes disponíveis |--------------------
	[[ -z $tempRedes ]] && echo "Não há redes sem-fio disponíveis para ${INTERFACES[$1]}..." && return 1

	# --------| Armazena cada rede num elemento da array ''REDES'' |-----
	local i=-1
	for tempRede in $tempRedes; do
		REDES[$((++i))]=$tempRede
	done
	return 0
}

# ------| DEFINE A INTERFACE A USAR |------------------------------------------------
# A função retorna o número de índice da interface selecionada na array INTERFACES
# Se não houver interface disponível, a função retorna 255
define_interface(){
	escr_secao "INTERFACES DE REDE DISPONÍVEIS"

	# ---------| Se houver mais de uma interface, pergunta ao usuário qual usar
	if [[ ${#INTERFACES[@]} -gt 0 ]]; then
		escr_subsecao "Escolher interface (vazio=0):"
		local i=0
		for tempNic in ${INTERFACES[@]}; do
			escr_item "[ $i ]. $tempNic"
			i=$((i+1))
		done

		escr_item "[ $i ]. Sair"

		# variável que armazena a interface escolhida
		local numNic=-1
		while [[ 10#${numNic/*[a-zA-Z]*/-1} -gt ${#INTERFACES[@]} || 10#${numNic/*[a-zA-Z]*/-1} -lt 0 ]]
		do
			escr_item "> "
			read numNic
		done
	else
		escr_subsecao "NÃO FOI POSSÍVEL LOCALIZAR INTERFACES DE REDE SEM-FIO"
		sleep 3
		return 255
	fi

	# ---------| Define a primeira interface encontrada como padrão |----
	INTERFACE=${INTERFACES[${numNic:-0}]}
	return ${numNic:-0}
}

# ------| DEFINE A REDE A SE CONECTAR |-----------------------------------------------
# A função retorna o número de índice da rede selecionada na array REDES
# Se não houver rede disponível, a função retorna 255
define_rede(){
	escr_secao "REDES DISPONÍVEIS PARA ${INTERFACES[$1]^^}"

	# --------| Se houver mais de uma rede, pergunta ao usuário qual usar
	if [[ ${#REDES[@]} -gt 0 ]]; then
		escr_subsecao "Escolher um rede (vazio = 0):"
		local i=-1

		# Itera as redes disponíveis para escrever no menu
		for tempRede in ${REDES[@]}; do
			escr_item "> $((++i)) : $tempRede"
		done

		# variável que armazena a rede escolhida
		numRede=-1
		while [[ 10#${numRede/*[a-zA-Z]*/-1} -gt $(( ${#REDES[@]} - 1 )) || 10#${numRede/*[a-zA-Z]*/-1} -lt 0 ]]
		do
			escr_item "> "
			read numRede
		done
	else
		escr_subsecao "NÃO FOI POSSÍVEL LOCALIZAR REDES ATRAVÉS DE ${INTERFACES[$1]}"
		sleep 1
		escr_subsecao "TEM CERTEZA QUE ESSA INTERFACE SUPORTA CONEXÕES SEM-FIO?"
		sleep 2
		return 255
	fi

	# --------| Define a primeira rede encontrada como padrão |----------
	REDE=${REDES[${numRede:-0}]}
	return ${numRede:-0}
}

# -----| VERIFICA SE INTERFACE JÁ ESTÁ CONECTADA |------------------------------------
iface_conectada(){
	# Obtém rota padrão - se houver uma
	rotaPadrao=$(ip route | grep default | cut -d" " -f5)

	# Sai caso a interface escolhida estiver conectada
	if [[ $rotaPadrao = $1 ]]; then
		echo "$1 já está conectada à uma rede. Se deseja trocar, desconecte-a primeiramente."
		return 0
	fi
	return 1
}

# -----| CONFIGURA SENHA PARA A REDE $1 |----------------------------------------------
configura_senha(){
	read -p -s "Senha para rede $1 : " senha
	wpa_passphrase $1 $senha
	# WPA_CONF contém bloco de configurações da rede $2 ?
	local bloco_rede=$(grep $2 $wpa_iface | cut -d'"' -f2)
	if [[ ! -f $wpa_iface ]]; then
		read -p -s "Senha para $2: "
		wpa_passphrase $2 $senha > $wpa_iface
		chmod 600 $wpa_iface
	fi
}

# -----| CHECA PREDEFINIÇÕES SALVAS |---------------------------------------------------
carrega_predefinicoes(){
	# Reseta array PREDEFINICOES
	PREDEFINICOES=()

	obtem_interfaces
	local tempRedes
	local i=0

	# itera cada nome de interface de rede sem-fio achado no sistema
	for iface in ${INTERFACES[@]}; do

		# itera cada arquivo do diretório abaixo especificado
		for arq in /etc/wpa_supplicant/*; do

			# se existir um arquivo wpa_supplicant.conf para a interface do loop, armazena
			# nome das redes disponíveis para tal interface na array PREDEFINICOES
			if [[ ${arq##*/} = "wpa_supplicant_$iface.conf" ]]; then

				tempRede=$(grep -i ssid $arq | cut -d'"' -f2)

				# itera os nomes de redes para armazenar em PREDEFINIÇOES
				for rede in $tempRede; do
					PREDEFINICOES[$i]="$iface:$rede"
					i=$((i+1))
				done
			fi
		done
	done
}

# ------| MOSTRA MENU COM INTERFACES E REDES JÁ CONFIGURADAS |-------------------------
menu_predefinicoes(){
	escr_secao "ESCOLHER CONEXÃO PREDEFINIDA ( VAZIO = 0 )"
	local subsecao=''
	local i

	# itera array PREDEFINICOES
	for ((i=0; i < ${#PREDEFINICOES[@]}; i=i+1)); do
		def=${PREDEFINICOES[$i]}

		# separa cada predefinição para mostrar no menu
		iface=$(cut -d":" -f1 <<< $def)
		rede=$(cut -d":" -f2 <<< $def)

		# só escreve uma nova subseção se for diferente da anterior (interfaces diferentes)
		if [[ "$iface" != "$subsecao" ]]; then
			escr_subsecao "Redes configuradas para $iface"
			subsecao=$iface
		fi

		# escreve rede atual para interface (seção) atual
		escr_item "[ $i ]. $rede"
	done

	# dá outras opções de escolha ao usuário
	escr_subsecao "Selecionar outras opções"
	escr_item "[ $i ]. Apagar todas predefinições"
	escr_item "[ $((++i)) ]. Mostrar mais opções"
	escr_item "[ $((++i)) ]. Sair"

	# variável que armazena valor da opção escolhida no menu
	local opcao=-1

	# só sai do loop quando ''opcao'' estiver entre 0 e o nº de sair, ou se ''opcao'' for vazio
	while [[ 10#${opcao/*[a-zA-Z]*/-1} -lt 0 || 10#${opcao/*[a-zA-Z]*/-1} -gt $i ]]; do
		escr_item "> "
		read opcao
	done

	# se estiver vazio, o padrão é zero = a primeira predefinição do menu
	return ${opcao:-0}
}

# ------| DELETA PREDEFINIÇÕES DE INTERFACES E REDES |-----------------------------------
apagar_predefinicoes(){
	escr_secao "APAGAR PREDEFINIÇÕES"
	escr_subsecao "Apagar todas as redes já configuradas? (vazio = n)"
	escr_item "[ s ]. Sim"
	escr_item "[ n ]. Não, cancelar"

	# variável que armazena valor da opção escolhida no menu
	local opcao=-1
	while [[ "$opcao" != "s" && "$opcao" != "n" ]]; do
		escr_item "> "
		read opcao
	done

	local controle=0

	if [[ "$opcao" = "s" ]]; then
		local tempRedes
		local i=0

		# itera cada nome de interface de rede sem-fio achado no sistema
		for iface in ${INTERFACES[@]}; do

			# itera cada arquivo do diretório abaixo especificado
			for arq in /etc/wpa_supplicant/*; do

				# apaga arquivo wpa_supplicant_nome-interface.conf para a interface do loop
				if [[ ${arq##*/} = "wpa_supplicant_$iface.conf" ]]; then
					( ! rm $arq ) && controle=1
				fi
			done
		done
	else
		controle=2
	fi

	# 0 = arquivos removidos com sucesso
	# 1 = algum arquivo não pode ser removido
	# 2 = ação cancelada
	case $control in
		0) escr_item "Configurações removidas com sucesso!" ;;
		1) escr_item "Um ou mais arquivos não puderam ser removidos." ;;
		2) escr_item "Ação cancelada!" ;;
	esac
	return $controle
}

# -----| Checa se arquivo wpa_supplicant_interface.conf |------------------------------------------------
# -----| contém dados necessários para iniciar conexão  |------------------------------------------------
verifica_wpa_conf(){
	wpaConf="$WPA_CONF_DIR/wpa_supplicant_$2.conf"

	# Procura a linha do arquivo que permite conexão com wpa_cli
	ctrl_interface=$(grep ctrl_interface "$wpaConf")

	# Se a linha não estivar da forma correta ou não existir, o arquivo é editado  com comando sed
	if [[ -n "$ctrl_interface" && "$ctrl_interface" != 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel' ]]; then
		sed -i s/"^ctrl.*|^#ctrl.*"/"ctrl_interface=DIR=\/var\/run\/wpa_supplicant\ GROUP=wheel"/g "$wpaConf"
	elif [[ -z "$ctrl_interface" ]]; then
		sed -i "1i\ctrl_interface=DIR=\/var\/run\/wpa_supplicant\ GROUP=wheel" "$wpaConf"
	fi

	# Procura linha que permite wpa_cli fazer alterações no arquivo
	update_config=$(grep update_config "$wpaConf")

	# Se a linha não estivar da forma correta ou não existir, o arquivo é editado  com comando sed
	if [[ -n "$update_config" && "$update_config" != "update_config=1" ]]; then
		sed -i s/"^update_.*|^#update_.*"/"update_config=1"/g "$wpaConf"
	elif [[ -z "$update_config" ]]; then
		sed -i "2i\update_config=1" "$wpaConf"
	fi

	# Procura registro da rede selecionada dentro do arquivo
	rede=$(grep -i "$1" "$wpaConf" | cut -d'"' -f2)

	# Se tal rede não exister, inicia-se o wpa_passphrase para configurar a senha
	# da rede, e um novo bloco de configuração é criado
	if [[ -z "$rede" ]]; then
		( ! wpa_passphrase "$1"  >> "$WPA_CONF_DIR/wpa_supplicant_$2.conf" ) && return 1
		sed -i /#psk/d "$WPA_CONF_DIR/wpa_supplicant_$2.conf"
	fi
	return 0
}

inicia_wpa_supplicant(){
	processos_wpa=$(ps aux | grep wpa_supplicant)
	proc_wpa_iface=$(grep -Eo "wpa.*$1.conf$" <<< "$processos_wpa")
	if [[ -n "$proc_wpa_iface" ]]; then
		wpa_cli -i "$1" <<< $'reconfigure'
	else
		wpa_supplicant -B -D nl80211,wext -i "$1" -c "$WPA_CONF_DIR/wpa_supplicant_$1.conf"
	fi
}

# Conectar na rede sem-fio $1 através da interface $2
conectar_rede(){
	# verifica arquivo de configuração da interface
	verifica_wpa_conf "$1" "$2"
	local wpa_conf=$?

	# se estiver tudo certo, inicia procedimento de conexão
	if [[ $wpa_conf -eq 0 ]]; then

		# iniciar wpa_supplicant
		inicia_wpa_supplicant $2

		# pega as redes listadas nos blocos do arquivo de configuração
		local list_networks=$(wpa_cli -i "$2" <<< $'list_networks\nquit')

		# filtra as redes em busca do número (id) da rede específica selecionada pelo usuário
		local id_network=$(grep -i "$1" <<< "$list_networks" | cut -f1)

		# seleciona a rede escolhida
		wpa_cli -i $2 <<< $'select_network $id_network'

		# aguarda 6 segundos enquando o wpa_cli tenta se autenticar
		local i=0
		escr_item "Aguarde. Tentando autenticar"
		for i in {0..5}; do
			echo -n " ."
			sleep 1
		done

		# verifica se autenticou (COMPLETED = OK)
		estado=$(wpa_cli -i "$2" <<< $'status' | grep wpa_state | cut -d"=" -f2)
		if [[ "$estado" = "COMPLETED" ]]; then
			escr_item "Dispositivo autenticado com sucesso na rede $1 !"

			# aguarda 6 segundos enquando o dhclient solicita um IP
			local i=0
			escr_item "Solicitando endereço IP"
			killall dhclient
			dhclient "$2"
			for i in {0..5}; do
				echo -n " ."
				sleep 1
			done
		fi
	else
		escr_item "Ocorreu um erro ao tentar gravar a senha"
		return 1
	fi
}

sair(){
	escr_item "Obrigado por usar a Ferramenta de Conexão Sem-fio com autenticação WPA (fcsf-wpa)"
	sleep 2
	clear
	exit 0
}

# ===========================================================================
# ------------------------- | MÓDULO PRINCIPAL | ----------------------------
# ===========================================================================

menu_sem_predefinicoes(){
	obtem_interfaces
	define_interface
	local nIface=$?
	[[ $nIface -eq 255 ]] && echo && exit 1
	[[ $nIface -eq ${#INTERFACES[@]} ]] && sair
	obtem_redes $nIface
	define_rede $nIface
	local nRede=$?
	[[ $nRede -eq 255 ]] && echo && exit 1
	INTERFACE=${INTERFACES[$nIface]}
	REDE=${REDES[$nRede]}
}

menu_principal(){
	# verfica se os diretórios necessários existem
	checa_dirs

	# carrega as informações de interfaces e redes já usados anteriormente pelo script
	carrega_predefinicoes

	# armazena o número de predefinições encontradas
	local PREDFS_NUM=${#PREDEFINICOES[@]}
	local APAGAR_PREDFS=$PREDFS_NUM
	local MOSTRA_MAIS=$((PREDFS_NUM+1))
	local SAIR_MENU=$((PREDFS_NUM+2))

	if [[ $PREDFS_NUM -eq 0 ]]; then
		menu_sem_predefinicoes
	else
		menu_predefinicoes
		local escolha=$?

		case $escolha in

			# -----| Se escolha for uma das predefinições mostradas |----------------------------------
			[0-$((PREDFS_NUM-1))] )
				INTERFACE=$(cut -d ":" -f 1 <<< $predefinicao)
				REDE=$(cut -d ":" -f 2 <<< $predefinicao)
				;;

			# -----| Se escolhar for apagar todas as predefinições |------------------------------------
			$APAGAR_PREDFS )
				apagar_predefinicoes
				menu_principal
				;;

			# -----| Se escolha for Mostrar mais opções |-----------------------------------------------
			$MOSTRA_MAIS )
				menu_sem_predefinicoes
				;;

			# -----| Se escolha for sair |---------------------------------------------------------------
			$SAIR_MENU )
				sair
				;;
		esac
	fi

	conectar $REDE $INTERFACE
	[[ $? -eq 1 ]] && escr_item "Algo deu errado..." && menu_principal
}

menu_principal

# AFAZER:
# - implementar escolha de apagar somente uma predefinição selecionada
# - em iniciar_wpa() verficar processos por interfaces
# - em conectar() verificar se rede está ao alance
