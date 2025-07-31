#!/bin/bash

# Script para eliminar infraestructura de red en AWS
# Autor: Infraestructura automatizada
# Fecha: $(date)

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}🗑️ Iniciando eliminación de infraestructura de red...${NC}"

# Verificar si existe el archivo de configuración
if [ ! -f "network_config.txt" ]; then
    echo -e "${RED}❌ Error: No se encontró el archivo network_config.txt${NC}"
    echo -e "${YELLOW}💡 Asegúrate de haber ejecutado el script de creación primero${NC}"
    exit 1
fi

# Cargar configuración
source network_config.txt

echo -e "${YELLOW}📋 Configuración cargada:${NC}"
echo -e "   VPC ID: $VPC_ID"
echo -e "   Internet Gateway ID: $IGW_ID"
echo -e "   Subnet ID: $SUBNET_ID"
echo -e "   Route Table ID: $ROUTE_TABLE_ID"
echo -e "   Security Group ID: $SG_ID"
echo -e "   Región: $REGION"

# Confirmación antes de eliminar
echo -e "${RED}⚠️ ADVERTENCIA: Esta acción eliminará TODA la infraestructura de red${NC}"
read -p "¿Estás seguro de que quieres continuar? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}❌ Operación cancelada${NC}"
    exit 0
fi

# Función para verificar si un recurso existe
resource_exists() {
    local resource_type=$1
    local resource_id=$2
    
    case $resource_type in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids $resource_id --region $REGION &>/dev/null
            ;;
        "igw")
            aws ec2 describe-internet-gateways --internet-gateway-ids $resource_id --region $REGION &>/dev/null
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids $resource_id --region $REGION &>/dev/null
            ;;
        "route-table")
            aws ec2 describe-route-tables --route-table-ids $resource_id --region $REGION &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids $resource_id --region $REGION &>/dev/null
            ;;
    esac
}

# 1. Eliminar Security Group
echo -e "${YELLOW}🛡️ Eliminando Security Group...${NC}"
if resource_exists "security-group" $SG_ID; then
    aws ec2 delete-security-group \
        --group-id $SG_ID \
        --region $REGION
    echo -e "${GREEN}✅ Security Group eliminado: $SG_ID${NC}"
else
    echo -e "${YELLOW}⚠️ Security Group no encontrado: $SG_ID${NC}"
fi

# 2. Desasociar y eliminar Route Table (si no es la default)
echo -e "${YELLOW}🗺️ Eliminando Route Table...${NC}"
if resource_exists "route-table" $ROUTE_TABLE_ID; then
    # Obtener asociaciones de la route table
    ASSOCIATIONS=$(aws ec2 describe-route-tables \
        --route-table-ids $ROUTE_TABLE_ID \
        --region $REGION \
        --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
        --output text)
    
    # Desasociar route table de subnets
    if [ ! -z "$ASSOCIATIONS" ]; then
        for ASSOC_ID in $ASSOCIATIONS; do
            echo -e "${YELLOW}🔗 Desasociando Route Table: $ASSOC_ID${NC}"
            aws ec2 disassociate-route-table \
                --association-id $ASSOC_ID \
                --region $REGION
        done
    fi
    
    # Eliminar route table
    aws ec2 delete-route-table \
        --route-table-id $ROUTE_TABLE_ID \
        --region $REGION
    echo -e "${GREEN}✅ Route Table eliminada: $ROUTE_TABLE_ID${NC}"
else
    echo -e "${YELLOW}⚠️ Route Table no encontrada: $ROUTE_TABLE_ID${NC}"
fi

# 3. Eliminar Subnet
echo -e "${YELLOW}🏠 Eliminando Subnet...${NC}"
if resource_exists "subnet" $SUBNET_ID; then
    aws ec2 delete-subnet \
        --subnet-id $SUBNET_ID \
        --region $REGION
    echo -e "${GREEN}✅ Subnet eliminada: $SUBNET_ID${NC}"
else
    echo -e "${YELLOW}⚠️ Subnet no encontrada: $SUBNET_ID${NC}"
fi

# 4. Desasociar y eliminar Internet Gateway
echo -e "${YELLOW}🌐 Eliminando Internet Gateway...${NC}"
if resource_exists "igw" $IGW_ID; then
    # Desasociar Internet Gateway de VPC
    aws ec2 detach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID \
        --region $REGION
    
    # Eliminar Internet Gateway
    aws ec2 delete-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --region $REGION
    echo -e "${GREEN}✅ Internet Gateway eliminado: $IGW_ID${NC}"
else
    echo -e "${YELLOW}⚠️ Internet Gateway no encontrado: $IGW_ID${NC}"
fi

# 5. Eliminar VPC
echo -e "${YELLOW}📡 Eliminando VPC...${NC}"
if resource_exists "vpc" $VPC_ID; then
    # Esperar un momento para que se liberen las dependencias
    sleep 5
    
    aws ec2 delete-vpc \
        --vpc-id $VPC_ID \
        --region $REGION
    echo -e "${GREEN}✅ VPC eliminada: $VPC_ID${NC}"
else
    echo -e "${YELLOW}⚠️ VPC no encontrada: $VPC_ID${NC}"
fi

# 6. Eliminar archivo de configuración
echo -e "${YELLOW}💾 Eliminando archivo de configuración...${NC}"
rm -f network_config.txt
echo -e "${GREEN}✅ Archivo network_config.txt eliminado${NC}"

echo -e "${GREEN}🎉 ¡Infraestructura de red eliminada exitosamente!${NC}"
echo -e "${GREEN}📋 Todos los recursos de red han sido eliminados:${NC}"
echo -e "   ✅ Security Group"
echo -e "   ✅ Route Table"
echo -e "   ✅ Subnet"
echo -e "   ✅ Internet Gateway"
echo -e "   ✅ VPC"
echo -e "${YELLOW}📄 Archivo de configuración eliminado${NC}"