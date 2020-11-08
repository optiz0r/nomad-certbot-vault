job "certbot-nomad" {
    datacenters = ["dc1"]

    type = "batch"

    periodic {
        cron = "0 6 * * * *"
        prohibit_overlap = true
    }

    group "default" {
        count = 1

        restart {
            attempts = 10
            interval = "5m"
            delay = "25s"
            mode = "delay"
        }

        task "registry" {
            driver = "docker"

            config {
                image = "myregistry.example.com:5000/certbot-nomad:latest"
                args = [
                    "renew",
                ]
            }

            env {
                VAULT_ADDR = "https://vault.service.consul:8200"
            }

            vault {
                policies = ["certbot-nomad"]
                change_mode = "restart"
                env = true
            }

            resources {
                cpu = 100
                memory = 64
            }
        }
    }
}
