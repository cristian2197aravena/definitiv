//declarar constructor output y le daremos de nombre DNS publica para identificarlo
// debe llevar un argumento boligatorio que es value y el valor lo saca de instancia que tiene ese atributo y opcional desfription

//output "dns_publica" {
// value = aws_instance.mi_servidor.public_dns
//}

// para agregarlo el https y :8080 se interpola con "$"
output "dns_publica_servidor_1" {
  description = "DNS publica del servidor"
  value       = [for servidor in aws_instance.servidor : "http://${servidor.public_dns}:${var.puerto_servidor}"]
}


output "dns_load_balancer" {
  description = "DNS publica del Load balancer"
  value       = "http://${aws_lb.alb.dns_name}:${var.puerto_lb}"
}

//output "ip_v4" {
//    description = "IP V4 del servidor"
//  value = "http://${aws_instance.mi_servidor.public_ip}:8080"
//}