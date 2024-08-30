#!/bin/bash

SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDbC7fGQkGTjXERSAwLq7co5QXvahoXdG93m/Zx/+W1v+eme1ZohTCyi41MkcAJDr2KHSibwo6PE7WWjgYFAsZg/PNE6igI0D5VzC63T48tsK6ffxGFYy3rl0B/VyvHdfqe/vcw44zn6HRjF2q01DXV2NeSBZuJL+diclAcB+2jhrjha9iHWxxkJuxwFl76bAfhVdtNE6yC0It+aUtJLPT1ppcviGKpIyN1w6pGvWxk1pV+Pf6CdqU1FK05FeSPK+f34bSgIOin/DCNN6oBFgX2V5H/+Gf290bmlT9YGVSNZ0Y/HCK3Cetl3A+1j4YtbyANA3ju5mWeKeG8svzfphVRuOlKtwL+pVSrcnJuLIJqf4Nsq3PBAaPt9xzHk5vkmVfaMftQU0OXrgYhP2455SuuhpJe4LG3uyncRAXCK1AX7OoDI5jY6C4pZM00Vv+FOu5BYZLn28vr73B/rHBMzjnOCiouLbrYiCSL9VGtLcPTx4haoTWbm7fZSakyUhITI6M= alissonoliveira@ALISSON"
USER="devops"
PACKAGES="curl git jq apt-transport-https ca-certificates curl software-properties-common"


#!/bin/bash

# Verificação de variáveis de ambiente
if [ -z "$PACKAGES" ] || [ -z "$SSH_KEY" ] || [ -z "$USER" ]; then
    echo "Erro: Certifique-se de que as variáveis PACKAGES, SSH_KEY e USER estão definidas."
    exit 1
fi

# Atualização de pacotes e instalação
echo "Atualizando pacotes..."
sudo apt update -y && sudo apt install -y "$PACKAGES"

echo "Instalando o Docker"

# Validando se o docker está instalado
if [ ! command -v docker &> /dev/null ]; then
    echo "Instalando o Docker..."
    wget -O - https://get.docker.com/ | sudo bash
    echo "Adicionando o usuário $USER ao grupo do Docker"
    sudo usermod -aG docker $USER
else
    echo "Docker já está instalado"

# Validando e instalando o Kind
if [ ! command -v kind &> /dev/null ]; then
    echo "Instalando o Kind..."
    [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
    echo "Atribuindo permissão de execução ao Kind"
    sudo chmod +x kind
    echo "Movendo o Kind para o diretório /usr/local/bin"
    sudo mv -f kind /usr/local/bin/kind
else
    echo "Kind já está instalado"
fi

# Adicionar chave SSH ao arquivo authorized_keys se não existir
if ! grep -q -i "$SSH_KEY" /home/vagrant/.ssh/authorized_keys; then
    echo "Escrevendo a chave SSH no arquivo authorized_keys"
    echo "$SSH_KEY" >> /home/vagrant/.ssh/authorized_keys
else
    echo "Chave SSH já existente no arquivo authorized_keys"
fi

# Criar usuário se não existir
if ! id -u "$USER" > /dev/null 2>&1; then
    echo "Usuário: $USER não encontrado, criando usuário..."
    sudo useradd -m -d /home/"$USER" -s /bin/bash "$USER"
else
    echo "Usuário: $USER encontrado"
fi

# Adicionar usuário ao sudoers se necessário
if ! sudo test -f /etc/sudoers.d/"$USER"; then
    echo "Criando arquivo sudoers para o usuário $USER"
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$USER" > /dev/null

    # Validar o arquivo sudoers para garantir que não haja erros
    if ! sudo visudo -cf /etc/sudoers.d/"$USER"; then
        echo "Erro: O arquivo sudoers para $USER contém erros!"
        sudo rm /etc/sudoers.d/"$USER"
        exit 1
    fi
else
    echo "Arquivo sudoers já existente para o usuário $USER"
fi

# Copiar diretório .ssh do usuário vagrant para o usuário criado se necessário
if ! sudo test -f /home/"$USER"/.ssh/authorized_keys; then
    echo "Copiando o diretório .ssh do usuário vagrant para o usuário: $USER"
    sudo cp -r /home/vagrant/.ssh /home/"$USER"/
    sudo chown -R "$USER":"$USER" /home/"$USER"/.ssh

    # Garantir que as permissões estejam corretas
    sudo chmod 700 /home/"$USER"/.ssh
    sudo chmod 600 /home/"$USER"/.ssh/authorized_keys
else
    echo "Diretório .ssh já existente para o usuário $USER"
fi