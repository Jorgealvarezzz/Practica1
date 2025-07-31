#!/bin/bash

# Script para crear instancia EC2 usando la infraestructura de red existente
# Autor: Infraestructura automatizada
# Fecha: $(date)

set -e  # Salir si hay algún error

# Variables de configuración para EC2
AMI_ID="ami-0c02fb55956c7d316"  # Amazon Linux 2023 en us-east-1
INSTANCE_TYPE="t2.micro"
KEY_PAIR_NAME="mi-proyecto-keypair"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Iniciando creación de instancia EC2...${NC}"

# Verificar si existe el archivo de configuración de red
if [ ! -f "network_config.txt" ]; then
    echo -e "${RED}❌ Error: No se encontró el archivo network_config.txt${NC}"
    echo -e "${YELLOW}💡 Ejecuta primero el script de creación de red${NC}"
    exit 1
fi

# Cargar configuración de red
source network_config.txt

echo -e "${BLUE}📋 Usando configuración de red existente:${NC}"
echo -e "   VPC ID: $VPC_ID"
echo -e "   Subnet ID: $SUBNET_ID"
echo -e "   Security Group ID: $SG_ID"
echo -e "   Región: $REGION"

# 1. Verificar si el key pair existe, si no, crearlo
echo -e "${YELLOW}🔑 Verificando Key Pair...${NC}"
if aws ec2 describe-key-pairs --key-names $KEY_PAIR_NAME --region $REGION &>/dev/null; then
    echo -e "${GREEN}✅ Key Pair ya existe: $KEY_PAIR_NAME${NC}"
else
    echo -e "${YELLOW}🔑 Creando nuevo Key Pair...${NC}"
    aws ec2 create-key-pair \
        --key-name $KEY_PAIR_NAME \
        --region $REGION \
        --query 'KeyMaterial' \
        --output text > ${KEY_PAIR_NAME}.pem
    
    # Configurar permisos del archivo de clave
    chmod 400 ${KEY_PAIR_NAME}.pem
    echo -e "${GREEN}✅ Key Pair creado: $KEY_PAIR_NAME${NC}"
    echo -e "${YELLOW}🔐 Clave privada guardada en: ${KEY_PAIR_NAME}.pem${NC}"
fi

# 2. Crear script de user data para configuración inicial
echo -e "${YELLOW}📝 Preparando script de configuración inicial...${NC}"
cat > user_data.sh << 'EOF'
#!/bin/bash
# Actualizar el sistema
yum update -y

# Instalar utilidades básicas
yum install -y htop curl wget git

# Instalar Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Instalar docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Crear directorio para aplicaciones
mkdir -p /home/ec2-user/apps
chown ec2-user:ec2-user /home/ec2-user/apps

# Configurar mensaje de bienvenida
cat > /etc/motd << 'MOTD'
===============================================
🎉 ¡Bienvenido a tu instancia EC2!
===============================================
- Docker instalado y configurado
- Docker Compose disponible
- Directorio de apps: /home/ec2-user/apps
===============================================
MOTD

# Crear archivo de información del sistema
cat > /home/ec2-user/system_info.txt << 'INFO'
Instancia EC2 creada: $(date)
AMI: Amazon Linux 2023
Tipo: t2.micro
Docker: Instalado
Usuario: ec2-user
INFO

chown ec2-user:ec2-user /home/ec2-user/system_info.txt

# Log de finalización
echo "$(date): User data script completado" >> /var/log/user-data.log
EOF

# 3. Crear la instancia EC2
echo -e "${YELLOW}🖥️ Creando instancia EC2...${NC}"
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_PAIR_NAME \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --user-data file://user_data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-instance}]" \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo crear la instancia EC2${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Instancia EC2 creada: $INSTANCE_ID${NC}"

# 4. Esperar a que la instancia esté running
echo -e "${YELLOW}⏳ Esperando a que la instancia esté en estado 'running'...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# 5. Obtener información de la instancia
echo -e "${YELLOW}📊 Obteniendo información de la instancia...${NC}"
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,State.Name]' \
    --output text)

PUBLIC_IP=$(echo $INSTANCE_INFO | cut -d' ' -f1)
PRIVATE_IP=$(echo $INSTANCE_INFO | cut -d' ' -f2)
STATE=$(echo $INSTANCE_INFO | cut -d' ' -f3)

# 6. Guardar configuración de EC2
echo -e "${YELLOW}💾 Guardando configuración de EC2...${NC}"
cat > ec2_config.txt << EOF
INSTANCE_ID=$INSTANCE_ID
PUBLIC_IP=$PUBLIC_IP
PRIVATE_IP=$PRIVATE_IP
KEY_PAIR_NAME=$KEY_PAIR_NAME
AMI_ID=$AMI_ID
INSTANCE_TYPE=$INSTANCE_TYPE
REGION=$REGION
PROJECT_NAME=$PROJECT_NAME
EOF

# 7. Limpiar archivos temporales
rm -f user_data.sh

echo -e "${GREEN}🎉 ¡Instancia EC2 creada exitosamente!${NC}"
echo -e "${GREEN}📋 Información de la instancia:${NC}"
echo -e "   Instance ID: $INSTANCE_ID"
echo -e "   Estado: $STATE"
echo -e "   IP Pública: $PUBLIC_IP"
echo -e "   IP Privada: $PRIVATE_IP"
echo -e "   Key Pair: $KEY_PAIR_NAME"
echo -e "   Tipo: $INSTANCE_TYPE"

echo -e "${BLUE}🔌 Comandos útiles:${NC}"
echo -e "   Conectar por SSH:"
echo -e "   ${YELLOW}ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$PUBLIC_IP${NC}"
echo ""
echo -e "   Verificar estado:"
echo -e "   ${YELLOW}aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION${NC}"

echo -e "${YELLOW}📄 Configuración guardada en: ec2_config.txt${NC}"
echo -e "${YELLOW}🔐 Clave SSH disponible en: ${KEY_PAIR_NAME}.pem${NC}"

# Esperar a que los status checks pasen
echo -e "${YELLOW}⏳ Esperando a que pasen los status checks (esto puede tomar 2-3 minutos)...${NC}"
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID --region $REGION

echo -e "${GREEN}✅ ¡La instancia está lista y completamente funcional!${NC}"
echo -e "${GREEN}🚀 Puedes conectarte ahora usando SSH${NC}"