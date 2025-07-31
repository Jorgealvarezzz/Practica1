#!/bin/bash

# Script para eliminar instancia EC2 y recursos relacionados
# Autor: Infraestructura automatizada
# Fecha: $(date)

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}🗑️ Iniciando eliminación de instancia EC2...${NC}"

# Verificar si existe el archivo de configuración de EC2
if [ ! -f "ec2_config.txt" ]; then
    echo -e "${RED}❌ Error: No se encontró el archivo ec2_config.txt${NC}"
    echo -e "${YELLOW}💡 Asegúrate de haber ejecutado el script de creación de EC2 primero${NC}"
    exit 1
fi

# Cargar configuración de EC2
source ec2_config.txt

echo -e "${BLUE}📋 Configuración cargada:${NC}"
echo -e "   Instance ID: $INSTANCE_ID"
echo -e "   IP Pública: $PUBLIC_IP"
echo -e "   IP Privada: $PRIVATE_IP"
echo -e "   Key Pair: $KEY_PAIR_NAME"
echo -e "   Región: $REGION"

# Confirmación antes de eliminar
echo -e "${RED}⚠️ ADVERTENCIA: Esta acción eliminará la instancia EC2 y recursos relacionados${NC}"
echo -e "${YELLOW}📋 Recursos que serán eliminados:${NC}"
echo -e "   • Instancia EC2: $INSTANCE_ID"
echo -e "   • Key Pair: $KEY_PAIR_NAME"
echo -e "   • Archivo de clave privada: ${KEY_PAIR_NAME}.pem"
echo -e "   • Archivos de configuración"
echo ""
read -p "¿Estás seguro de que quieres continuar? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}❌ Operación cancelada${NC}"
    exit 0
fi

# Función para verificar si la instancia existe
instance_exists() {
    aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null | grep -v "terminated" &>/dev/null
}

# 1. Verificar estado actual de la instancia
echo -e "${YELLOW}🔍 Verificando estado de la instancia...${NC}"
if instance_exists; then
    CURRENT_STATE=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    echo -e "${BLUE}📊 Estado actual de la instancia: $CURRENT_STATE${NC}"
    
    # 2. Terminar la instancia si no está ya terminada
    if [ "$CURRENT_STATE" != "terminated" ]; then
        echo -e "${YELLOW}🛑 Terminando instancia EC2...${NC}"
        aws ec2 terminate-instances \
            --instance-ids $INSTANCE_ID \
            --region $REGION
        
        echo -e "${YELLOW}⏳ Esperando a que la instancia se termine...${NC}"
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION
        echo -e "${GREEN}✅ Instancia terminada: $INSTANCE_ID${NC}"
    else
        echo -e "${YELLOW}⚠️ La instancia ya está terminada${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ La instancia no existe o ya está terminada${NC}"
fi

# 3. Eliminar Key Pair
echo -e "${YELLOW}🔑 Eliminando Key Pair...${NC}"
if aws ec2 describe-key-pairs --key-names $KEY_PAIR_NAME --region $REGION &>/dev/null; then
    aws ec2 delete-key-pair \
        --key-name $KEY_PAIR_NAME \
        --region $REGION
    echo -e "${GREEN}✅ Key Pair eliminado: $KEY_PAIR_NAME${NC}"
else
    echo -e "${YELLOW}⚠️ Key Pair no encontrado: $KEY_PAIR_NAME${NC}"
fi

# 4. Eliminar archivo de clave privada
echo -e "${YELLOW}🔐 Eliminando archivo de clave privada...${NC}"
if [ -f "${KEY_PAIR_NAME}.pem" ]; then
    rm -f ${KEY_PAIR_NAME}.pem
    echo -e "${GREEN}✅ Archivo de clave eliminado: ${KEY_PAIR_NAME}.pem${NC}"
else
    echo -e "${YELLOW}⚠️ Archivo de clave no encontrado: ${KEY_PAIR_NAME}.pem${NC}"
fi

# 5. Limpiar snapshots de EBS (si los hay)
echo -e "${YELLOW}💾 Verificando snapshots asociados...${NC}"
SNAPSHOTS=$(aws ec2 describe-snapshots \
    --owner-ids self \
    --region $REGION \
    --query "Snapshots[?Description && contains(Description, '$INSTANCE_ID')].SnapshotId" \
    --output text)

if [ ! -z "$SNAPSHOTS" ]; then
    echo -e "${YELLOW}🗑️ Eliminando snapshots asociados...${NC}"
    for SNAPSHOT_ID in $SNAPSHOTS; do
        aws ec2 delete-snapshot \
            --snapshot-id $SNAPSHOT_ID \
            --region $REGION
        echo -e "${GREEN}✅ Snapshot eliminado: $SNAPSHOT_ID${NC}"
    done
else
    echo -e "${BLUE}ℹ️ No se encontraron snapshots asociados${NC}"
fi

# 6. Verificar y limpiar volúmenes EBS no asociados
echo -e "${YELLOW}💽 Verificando volúmenes EBS disponibles...${NC}"
AVAILABLE_VOLUMES=$(aws ec2 describe-volumes \
    --region $REGION \
    --filters "Name=status,Values=available" "Name=tag:Name,Values=*${PROJECT_NAME}*" \
    --query 'Volumes[].VolumeId' \
    --output text)

if [ ! -z "$AVAILABLE_VOLUMES" ]; then
    echo -e "${YELLOW}🗑️ Eliminando volúmenes EBS no asociados...${NC}"
    for VOLUME_ID in $AVAILABLE_VOLUMES; do
        aws ec2 delete-volume \
            --volume-id $VOLUME_ID \
            --region $REGION
        echo -e "${GREEN}✅ Volumen EBS eliminado: $VOLUME_ID${NC}"
    done
else
    echo -e "${BLUE}ℹ️ No se encontraron volúmenes EBS disponibles para eliminar${NC}"
fi

# 7. Eliminar archivos de configuración
echo -e "${YELLOW}📄 Eliminando archivos de configuración...${NC}"
if [ -f "ec2_config.txt" ]; then
    rm -f ec2_config.txt
    echo -e "${GREEN}✅ Archivo ec2_config.txt eliminado${NC}"
fi

# 8. Mostrar resumen final
echo -e "${GREEN}🎉 ¡Instancia EC2 y recursos relacionados eliminados exitosamente!${NC}"
echo -e "${GREEN}📋 Recursos eliminados:${NC}"
echo -e "   ✅ Instancia EC2: $INSTANCE_ID"
echo -e "   ✅ Key Pair: $KEY_PAIR_NAME"
echo -e "   ✅ Archivo de clave privada"
echo -e "   ✅ Snapshots asociados (si los había)"
echo -e "   ✅ Volúmenes EBS disponibles (si los había)"
echo -e "   ✅ Archivos de configuración"

echo -e "${BLUE}💡 Nota importante:${NC}"
echo -e "   La infraestructura de red (VPC, Subnet, etc.) sigue activa."
echo -e "   Usa el script de eliminación de red si también quieres eliminarla."

echo -e "${YELLOW}🏁 Proceso de eliminación completado${NC}"