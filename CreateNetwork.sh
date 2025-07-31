#!/bin/bash

# Script para crear infraestructura de red en AWS
# Autor: Infraestructura automatizada
# Fecha: $(date)

set -e  # Salir si hay algún error

# Variables de configuración
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
REGION="us-east-1"
AZ="${REGION}a"
PROJECT_NAME="mi-proyecto"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Iniciando creación de infraestructura de red...${NC}"

# 1. Crear VPC
echo -e "${YELLOW}📡 Creando VPC...${NC}"
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
    --region $REGION \
    --query 'Vpc.VpcId' \
    --output text)

if [ -z "$VPC_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo crear la VPC${NC}"
    exit 1
fi

echo -e "${GREEN}✅ VPC creada: $VPC_ID${NC}"

# 2. Habilitar DNS hostname y resolution
echo -e "${YELLOW}🔧 Configurando DNS en VPC...${NC}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support --region $REGION

# 3. Crear Internet Gateway
echo -e "${YELLOW}🌐 Creando Internet Gateway...${NC}"
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
    --region $REGION \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

echo -e "${GREEN}✅ Internet Gateway creado: $IGW_ID${NC}"

# 4. Asociar Internet Gateway con VPC
echo -e "${YELLOW}🔗 Asociando Internet Gateway con VPC...${NC}"
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION

# 5. Crear Subnet pública
echo -e "${YELLOW}🏠 Creando Subnet pública...${NC}"
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET_CIDR \
    --availability-zone $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-subnet}]" \
    --region $REGION \
    --query 'Subnet.SubnetId' \
    --output text)

echo -e "${GREEN}✅ Subnet creada: $SUBNET_ID${NC}"

# 6. Habilitar auto-assign public IP
echo -e "${YELLOW}🔧 Configurando auto-asignación de IP pública...${NC}"
aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_ID \
    --map-public-ip-on-launch \
    --region $REGION

# 7. Crear Route Table
echo -e "${YELLOW}🗺️ Creando Route Table...${NC}"
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
    --region $REGION \
    --query 'RouteTable.RouteTableId' \
    --output text)

echo -e "${GREEN}✅ Route Table creada: $ROUTE_TABLE_ID${NC}"

# 8. Agregar ruta al Internet Gateway
echo -e "${YELLOW}🛤️ Configurando ruta hacia Internet Gateway...${NC}"
aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $REGION

# 9. Asociar Route Table con Subnet
echo -e "${YELLOW}🔗 Asociando Route Table con Subnet...${NC}"
aws ec2 associate-route-table \
    --route-table-id $ROUTE_TABLE_ID \
    --subnet-id $SUBNET_ID \
    --region $REGION

# 10. Crear Security Group
echo -e "${YELLOW}🛡️ Creando Security Group...${NC}"
SG_ID=$(aws ec2 create-security-group \
    --group-name "${PROJECT_NAME}-sg" \
    --description "Security Group para ${PROJECT_NAME}" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-sg}]" \
    --region $REGION \
    --query 'GroupId' \
    --output text)

echo -e "${GREEN}✅ Security Group creado: $SG_ID${NC}"

# 11. Configurar reglas del Security Group
echo -e "${YELLOW}🔐 Configurando reglas del Security Group...${NC}"

# SSH (puerto 22)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $REGION

# HTTP (puerto 80)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $REGION

# HTTPS (puerto 443)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $REGION

# 12. Guardar IDs en archivo para usar en otros scripts
echo -e "${YELLOW}💾 Guardando configuración...${NC}"
cat > network_config.txt << EOF
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
SUBNET_ID=$SUBNET_ID
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
SG_ID=$SG_ID
REGION=$REGION
PROJECT_NAME=$PROJECT_NAME
EOF

echo -e "${GREEN}🎉 ¡Infraestructura de red creada exitosamente!${NC}"
echo -e "${GREEN}📋 Resumen de recursos creados:${NC}"
echo -e "   VPC ID: $VPC_ID"
echo -e "   Internet Gateway ID: $IGW_ID"
echo -e "   Subnet ID: $SUBNET_ID"
echo -e "   Route Table ID: $ROUTE_TABLE_ID"
echo -e "   Security Group ID: $SG_ID"
echo -e "${YELLOW}📄 Configuración guardada en: network_config.txt${NC}"