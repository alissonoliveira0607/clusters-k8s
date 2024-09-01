#!/bin/bash

SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDbC7fGQkGTjXERSAwLq7co5QXvahoXdG93m/Zx/+W1v+eme1ZohTCyi41MkcAJDr2KHSibwo6PE7WWjgYFAsZg/PNE6igI0D5VzC63T48tsK6ffxGFYy3rl0B/VyvHdfqe/vcw44zn6HRjF2q01DXV2NeSBZuJL+diclAcB+2jhrjha9iHWxxkJuxwFl76bAfhVdtNE6yC0It+aUtJLPT1ppcviGKpIyN1w6pGvWxk1pV+Pf6CdqU1FK05FeSPK+f34bSgIOin/DCNN6oBFgX2V5H/+Gf290bmlT9YGVSNZ0Y/HCK3Cetl3A+1j4YtbyANA3ju5mWeKeG8svzfphVRuOlKtwL+pVSrcnJuLIJqf4Nsq3PBAaPt9xzHk5vkmVfaMftQU0OXrgYhP2455SuuhpJe4LG3uyncRAXCK1AX7OoDI5jY6C4pZM00Vv+FOu5BYZLn28vr73B/rHBMzjnOCiouLbrYiCSL9VGtLcPTx4haoTWbm7fZSakyUhITI6M= alissonoliveira@ALISSON"
USER="devops"
PACKAGES="curl gnupg2 gpg software-properties-common apt-transport-https ca-certificates jq net-tools make"

# Verificação de variáveis de ambiente
if [ -z "$PACKAGES" ] || [ -z "$SSH_KEY" ] || [ -z "$USER" ]; then
    echo "Erro: Certifique-se de que as variáveis PACKAGES, SSH_KEY e USER estão definidas."
    exit 1
fi

echo "Desabilitando a swap"
sudo sed -i 's/^\([^#]*\bswap\b\)/#\1/g' /etc/fstab
sudo swapoff -a


echo "Atualizando o kernel... Correção: control-plane node setup not starting · Issue #2744 · kubernetes-sigs/kind"
echo fs.inotify.max_user_watches=655360 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_instances=1280 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p


# Atualização de pacotes e instalação
echo "Atualizando pacotes..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y $PACKAGES

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

# Função para instalar o Docker
install_docker() {
    echo "Instalando o Docker..."
    wget -qO- https://get.docker.com/ | sudo bash
    sudo usermod -aG docker $USER
}

# Verificando se o Docker está instalado
if ! command -v docker &> /dev/null; then
    install_docker
else
    echo "Docker já está instalado"
fi


echo "Reiniciando o docker"
sudo systemctl restart docker
sleep 20

# Configurando o containerd
echo "Configurando o containerd..."
sudo bash -c 'containerd config default > /etc/containerd/config.toml'

echo "Reiniciando o containerd"
sudo systemctl restart containerd


# Função para instalar o Kind
install_kind() {
    echo "Instalando o Kind..."
    [ "$(uname -m)" = "x86_64" ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
    chmod +x kind
    sudo mv -f kind /usr/local/bin/kind
}

# Verificando se o Kind está instalado
if ! command -v kind &> /dev/null; then
    install_kind
else
    echo "Kind já está instalado"
fi


# Criando o cluster Kind
echo "Criando o cluster Kind..."
sudo wget -qO config.yaml https://raw.githubusercontent.com/alissonoliveira0607/clusters-k8s/develop/Kind/config.yaml 
kind create cluster --config config.yaml --name devops

# Instalando os Tools do K8s
echo "Instalando os Tools do K8s..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Instalando o helm e helmfile
echo "Instalando o helm e helmfile..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash  
sudo wget -qO helmfile https://github.com/roboll/helmfile/releases/download/v0.144.0/helmfile_linux_amd64
chmod +x helmfile
sudo mv -f helmfile /usr/local/bin/helmfile

echo "Ajustando permissões do helm"
if [ -f /home/$USER/.kube/config ]; then
    sudo chmod go-rw /home/$USER/.kube/config
    sudo mv /root/.kube /home/devops/.kube
    sudo chown -R devops: /home/devops/.kube
    exit 0
fi
