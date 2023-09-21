//Define el privder de AWS
provider "aws" {
  region = local.region
}

// Variables locals, si tenemos valores repetidos agruparlos en bloques llamados locals y referenciarlos
locals {
  region = "eu-west-1"
  ami    = var.ubuntu_ami[local.region]
}

// data source SUBNET con for_each para no tener que copiar y pegar uno y otro.
data "aws_subnet" "public_subnet" {
  for_each          = var.servidores // recordar que se ejecuta sobre un map
  availability_zone = "${local.region}${each.value.az}"
}

// define una instancia EC2 con AMI ubuntu - SERVIDOR 1
resource "aws_instance" "servidor" {
  for_each      = var.servidores
  ami           = local.ami
  instance_type = var.tipo_instancia
  subnet_id     = data.aws_subnet.public_subnet[each.key].id // capturamos la key que seria ser-1 o ser-2 dentro de las variables

  //Asociar instancia con Security groups y colocamos una referencia al SG
  vpc_security_group_ids = [aws_security_group.mi_grupo_de_seguridad.id]


  //Comandos para que ejecute un servidor en puerto 8080 y muestre fichero ondex.html con un mensaje

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y busybox-static
              echo "Hola Terraformers! Soy ${each.value.nombre}" > index.html
              nohup busybox httpd -f -p ${var.puerto_servidor} &
              EOF         
  tags = {
    Name = each.value.nombre
  }
}

//Grupo de seguridad con acceso al puerto 8080
resource "aws_security_group" "mi_grupo_de_seguridad" {
  name   = "primer-servidor-sg"
  vpc_id = data.aws_vpc.default.id
  //vamos a definir el ingress que tendria el bloque CIDR todas las ip
  ingress {
    security_groups = [aws_security_group.alb.id] // todas las ip
    description     = "Acceso al puerto 8080 desde el exterior"
    from_port       = var.puerto_servidor // puerto que vamos a abrir con la to_port
    to_port         = var.puerto_servidor
    protocol        = "TCP" // protocolo que utilizaremos
  }

    ingress {
    cidr_blocks = ["0.0.0.0/0"] // todas las ip
    description = "SSH"
    from_port   = 22 // puerto que vamos a abrir con la to_port
    to_port     = 22
    protocol    = "TCP"
  }
}

// Load balancer
// Una de las ventaja de usar LB es que podemos mapeor el puerto 80 al puerto 8080 de nuestro servidor y 
// puerto 80 es mas conveniente ya que la url se queda mas limpia sin poner el :8080
resource "aws_lb" "alb" {
  load_balancer_type = "application"
  name               = "terraformers-alb"
  security_groups    = [aws_security_group.alb.id] // va a definir que podamos acceder al load balancer ... definimos uno nuevo
  subnets            = [for subnet in data.aws_subnet.public_subnet : subnet.id]
  // para cada subnet en toda las data source de tipo aws_subnet con nombre public_subnet hasta ahora itera una por una... 
  //el nombre del iterador era subnet accedo a una en concreto y obtengo el ID
}

// definimos un nuevo SG que permita accedo al puerto 80 desde el exterior
resource "aws_security_group" "alb" {
  name = "alb-sg"

  ingress {
    cidr_blocks = ["0.0.0.0/0"] // todas las ip
    description = "SSH"
    from_port   = 22 // puerto que vamos a abrir con la to_port
    to_port     = 22
    protocol    = "TCP"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"] // todas las ip
    description = "Acceso al puerto 80 desde el exterior"
    from_port   = var.puerto_lb // puerto que vamos a abrir con la to_port
    to_port     = var.puerto_lb
    protocol    = "TCP"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"] // todas las ip
    description = "Acceso al puerto 8080 de nuestros servidores"
    from_port   = var.puerto_servidor // puerto que vamos a abrir con la to_port
    to_port     = var.puerto_servidor
    protocol    = "TCP"
  }
}

//DS:bloque de código que permite hacer querys de datos sobre recuros que noestamos manejando dese TF
//Data Source para obtener el ID de la VPC por defecto que se asigna ( la ocupo en aws-alb-target-group)
data "aws_vpc" "default" {
  default = true // si esta en true devuelve la vpc por defecto que hay en aws
}

// Es una practica dentro de tf si no hay otro recurso de este tipo colocarle THIS
// Permite enrutar tráfico desde el LB a nuestras instancias
resource "aws_lb_target_group" "this" {
  name     = "terraformers-alb-target-group"
  port     = var.puerto_lb
  vpc_id   = data.aws_vpc.default.id // Usamos un data source para sacar el id de la vpc
  protocol = "HTTP"

  // Ahora obliga a definir los ---
  // como tenemos target e instancias definidas debemos indicar cual esta heal chetk para que el LB rediriga a las inatancias que estan healtcheck

  health_check {
    enabled  = true
    matcher  = "200" // si contesta con un status code 200 que es por defecto cuando llamos al index.html asi estaria bien si no roto.
    path     = "/"
    port     = var.puerto_servidor
    protocol = "HTTP"
  }
}

// Attachment -> Como cada una de nuestras instancias se conectan con el targetr group, es una por cada instancia
resource "aws_lb_target_group_attachment" "servidor" {
  for_each = var.servidores

  // Ahora tenemos que acceder al identificador de cada una de las instancias quee tenemos.
  target_group_arn = aws_lb_target_group.this.arn       // arn es un atribut y this es el nombre del tg
  target_id        = aws_instance.servidor[each.key].id // es nuestra instancia sea el servidor en este caso y obtiene el ID
  port             = var.puerto_servidor                // puerto quer tenemos abierto en nuestra maquina
}

//Se necesita en el LB tener un listener para que nos redirigida toda las request entrantes por un puerto nos lo rediriga hacia otro puerto
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.alb.arn // referenciamso al lb nombre y atributo arn
  port              = var.puerto_lb
  protocol          = "HTTP"

  // Accion a tomar, diremos que hara forward de las peticiones que nos entran hacia el tg
  default_action {
    target_group_arn = aws_lb_target_group.this.arn
    type             = "forward"
  }
}