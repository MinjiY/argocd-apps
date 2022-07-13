function(
    is_offline="false",
    private_registry="registry.tmaxcloud.org",
    JAEGER_VERSION="1.27",
    cluster_name="master",
    tmax_client_secret="tmax_client_secret",
    HYPERAUTH_DOMAIN="hyperauth.domain",
    GATEKEER_VERSION="10.0.0",
    CUSTOM_DOMAIN_NAME="custom-domain",
    CUSTOM_CLUSTER_ISSUER="tmaxcloud-issuer",
    jaeger_subdomain="jaeger",
    storage_type="opensearch",
    timezone="UTC",
)

local target_registry = if is_offline == "false" then "" else private_registry + "/";
local REDIRECT_URL = jaeger_subdomain + "." + CUSTOM_DOMAIN_NAME;

[
  {
    "apiVersion": "v1",
    "kind": "ServiceAccount",
    "metadata": {
      "name": "jaeger-service-account",
      "namespace": "istio-system",
      "labels": {
        "app": "jaeger"
      }
    }
  },
  {
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRole",
    "metadata": {
      "name": "jaeger-istio-system",
      "labels": {
        "app": "jaeger"
      }
    },
    "rules": [
      {
        "apiGroups": [
          "extensions",
          "apps"
        ],
        "resources": [
          "deployments"
        ],
        "verbs": [
          "get",
          "list",
          "create",
          "patch",
          "update",
          "delete"
        ]
      },
      {
        "apiGroups": [
          ""
        ],
        "resources": [
          "pods",
          "services"
        ],
        "verbs": [
          "get",
          "list",
          "watch",
          "create",
          "delete"
        ]
      },
      {
        "apiGroups": [
          "networking.k8s.io"
        ],
        "resources": [
          "ingresses"
        ],
        "verbs": [
          "get",
          "list",
          "watch",
          "create",
          "delete",
          "update"
        ]
      },
      {
        "apiGroups": [
          "apps"
        ],
        "resources": [
          "daemonsets"
        ],
        "verbs": [
          "get",
          "list",
          "watch",
          "create",
          "delete",
          "update"
        ]
      }
    ]
  },
  {
    "kind": "ClusterRoleBinding",
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "metadata": {
      "name": "jaeger-istio-system"
    },
    "subjects": [
      {
        "kind": "ServiceAccount",
        "name": "jaeger-service-account",
        "namespace": "istio-system"
      }
    ],
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "ClusterRole",
      "name": "jaeger-istio-system"
    }
  },
  {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
      "name": "jaeger-configuration",
      "namespace": "istio-system",
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/name": "jaeger"
      }
    },
    "data": {
      "span-storage-type": "opensearch",
      "collector": std.join("\n", 
        [
          "es:",
          "  server-urls: https://opensearch.kube-logging.svc:9200",
          "  tls:",
          "    enabled: true",
          "    ca: /ca/cert/ca.crt",
          "    cert: /ca/cert/tls.crt",
          "    key: /ca/cert/tls.key",
          "  username: admin",
          "  password: admin",
          "collector:",
          "  zipkin:",
          "    host-port: 9411"
        ]
      ),
      "query": std.join("\n",
        [
          "es:",
          "  server-urls: https://opensearch.kube-logging.svc:9200",
          "  tls:",
          "    enabled: true",
          "    ca: /ca/cert/ca.crt",
          "    cert: /ca/cert/tls.crt",
          "    key: /ca/cert/tls.key",
          "  username: admin",
          "  password: admin"
        ]
      ),
      "agent": std.join("\n",
        [
          "reporter:",
          "  grpc:",
          "    host-port: \"jaeger-collector:14250\""
        ]
      )
    }
  },
  {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "namespace": "istio-system",
      "name": "jaeger-collector",
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "collector"
      }
    },
    "spec": {
      "selector": {
        "matchLabels": {
          "app": "jaeger"
        }
      },
      "replicas": 1,
      "strategy": {
        "type": "Recreate"
      },
      "template": {
        "metadata": {
          "labels": {
            "app": "jaeger",
            "app.kubernetes.io/name": "jaeger",
            "app.kubernetes.io/component": "collector"
          },
          "annotations": {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "14268"
          }
        },
        "spec": {
          "serviceAccountName": "jaeger-service-account",
          "containers": [
            {
              "image": std.join("", [target_registry, "docker.io/jaegertracing/jaeger-collector:", JAEGER_VERSION]),
              "name": "jaeger-collector",
              "args": [
                "--config-file=/conf/collector.yaml"
              ],
              "ports": [
                {
                  "containerPort": 14250,
                  "protocol": "TCP"
                },
                {
                  "containerPort": 14268,
                  "protocol": "TCP"
                },
                {
                  "containerPort": 9411,
                  "protocol": "TCP"
                }
              ],
              "readinessProbe": {
                "httpGet": {
                  "path": "/",
                  "port": 14269
                }
              },
              "volumeMounts": [
                {
                  "name": "jaeger-configuration-volume",
                  "mountPath": "/conf"
                },
                {
                  "name": "jaeger-certs",
                  "mountPath": "/ca/cert",
                  "readOnly": true
                }
              ] + ( if timezone != "UTC" then [
                  {
                    "name": "timezone-config",
                    "mountPath": "/etc/localtime"
                  }
                ] else []
              ),
              "env": [
                {
                  "name": "SPAN_STORAGE_TYPE",
                  "valueFrom": {
                    "configMapKeyRef": {
                      "name": "jaeger-configuration",
                      "key": "span-storage-type"
                    }
                  }
                }
              ]
            }
          ],
          "volumes": [
            {
              "name": "jaeger-certs",
              "secret":
                {
                  "defaultMode": 420,
                  "secretName": "jaeger-secret"
                }
            },
            {
              "configMap": {
                "name": "jaeger-configuration",
                "items": [
                  {
                    "key": "collector",
                    "path": "collector.yaml"
                  }
                ]
              },
              "name": "jaeger-configuration-volume"
            }
          ] + (
            if timezone != "UTC" then [
              {
                "name": "timezone-config",
                "hostPath": {
                  "path": std.join("", ["/usr/share/zoneinfo", timezone])
                }
              }
            ] else []
          )
        }
      }
    }
  },
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "namespace": "istio-system",
      "name": "jaeger-collector",
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "collector"
      }
    },
    "spec": {
      "ports": [
        {
          "name": "jaeger-collector-grpc",
          "port": 14250,
          "protocol": "TCP",
          "targetPort": 14250
        },
        {
          "name": "jaeger-collector-http",
          "port": 14268,
          "protocol": "TCP",
          "targetPort": 14268
        },
        {
          "name": "jaeger-collector-zipkin",
          "port": 9411,
          "protocol": "TCP",
          "targetPort": 9411
        }
      ],
      "selector": {
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "collector"
      },
      "type": "ClusterIP"
    }
  },
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "namespace": "istio-system",
      "name": "zipkin",
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "zipkin"
      }
    },
    "spec": {
      "ports": [
        {
          "name": "jaeger-collector-zipkin",
          "port": 9411,
          "protocol": "TCP",
          "targetPort": 9411
        }
      ],
      "selector": {
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "collector"
      },
      "type": "ClusterIP"
    }
  },
  {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "annotations": null,
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/component": "query",
        "app.kubernetes.io/name": "jaeger"
      },
      "name": "jaeger-query",
      "namespace": "istio-system"
    },
    "spec": {
      "replicas": 1,
      "selector": {
        "matchLabels": {
          "app": "jaeger"
        }
      },
      "strategy": {
        "type": "Recreate"
      },
      "template": {
        "metadata": {
          "annotations": {
            "prometheus.io/port": "16686",
            "prometheus.io/scrape": "true"
          },
          "creationTimestamp": null,
          "labels": {
            "app": "jaeger",
            "app.kubernetes.io/component": "query",
            "app.kubernetes.io/name": "jaeger"
          }
        },
        "spec": {
          "serviceAccountName": "jaeger-service-account",
          "containers": [
            {
              "args": [
                "--config-file=/conf/query.yaml"
              ],
              "env": [
                {
                  "name": "SPAN_STORAGE_TYPE",
                  "valueFrom": {
                    "configMapKeyRef": {
                      "key": "span-storage-type",
                      "name": "jaeger-configuration"
                    }
                  }
                },
                {
                  "name": "BASE_QUERY_PATH",
                  "value": "/api/jaeger"
                }
              ],
              "image": std.join("", [target_registry, "docker.io/jaegertracing/jaeger-query:", JAEGER_VERSION]),
              "imagePullPolicy": "IfNotPresent",
              "name": "jaeger-query",
              "ports": [
                {
                  "containerPort": 16686,
                  "protocol": "TCP"
                }
              ],
              "readinessProbe": {
                "failureThreshold": 3,
                "httpGet": {
                  "path": "/",
                  "port": 16687,
                  "scheme": "HTTP"
                },
                "initialDelaySeconds": 20,
                "periodSeconds": 5,
                "successThreshold": 1,
                "timeoutSeconds": 4
              },
              "resources": {},
              "terminationMessagePath": "/dev/termination-log",
              "terminationMessagePolicy": "File",
              "volumeMounts": [
                {
                  "mountPath": "/conf",
                  "name": "jaeger-configuration-volume"
                },
                {
                  "name": "secret",
                  "mountPath": "/ca/cert",
                  "readOnly": true
                }
              ] + ( if timezone != "UTC" then [
                  {
                    "name": "timezone-config",
                    "mountPath": "/etc/localtime"
                  }
                ] else []
              )
            }
          ],
          "dnsPolicy": "ClusterFirst",
          "restartPolicy": "Always",
          "schedulerName": "default-scheduler",
          "terminationGracePeriodSeconds": 30,
          "volumes": [
            {
              "name": "secret",
              "secret": {
                "defaultMode": 420,
                "secretName": "jaeger-secret"
              }
            },
            {
              "configMap": {
                "defaultMode": 420,
                "items": [
                  {
                    "key": "query",
                    "path": "query.yaml"
                  }
                ],
                "name": "jaeger-configuration"
              },
              "name": "jaeger-configuration-volume"
            }
          ] + (
            if timezone != "UTC" then [
              {
                "name": "timezone-config",
                "hostPath": {
                  "path": std.join("", ["/usr/share/zoneinfo", timezone])
                }
              }
            ] else []
          )
        }
      }
    }
  },
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/component": "query",
        "app.kubernetes.io/name": "jaeger"
      },
      "name": "jaeger-query",
      "namespace": "istio-system"
    },
    "spec": {
      "ports": [
        {
          "name": "jaeger-query",
          "port": 80,
          "protocol": "TCP",
          "targetPort": 16686
        }
      ],
      "selector": {
        "app.kubernetes.io/component": "query",
        "app.kubernetes.io/name": "jaeger"
      },
      "type": "LoadBalancer"
    }
  },
  {
    "apiVersion": "cert-manager.io/v1",
    "kind": "Certificate",
    "metadata": {
      "name": "jaeger-cert",
      "namespace": "istio-system"
    },
    "spec": {
      "secretName": "jaeger-secret",
      "usages": [
        "digital signature",
        "key encipherment",
        "server auth",
        "client auth"
      ],
      "dnsNames": [
          "tmax-cloud",
          "jaeger-query.istio-system.svc"
      ],
      "issuerRef": {
        "kind": "ClusterIssuer",
        "group": "cert-manager.io",
        "name": CUSTOM_CLUSTER_ISSUER
      }
    }
  },
  {
    "apiVersion": "apps/v1",
    "kind": "DaemonSet",
    "metadata": {
      "namespace": "istio-system",
      "name": "jaeger-agent",
      "labels": {
        "app": "jaeger",
        "app.kubernetes.io/name": "jaeger",
        "app.kubernetes.io/component": "agent"
      }
    },
    "spec": {
      "selector": {
        "matchLabels": {
          "app": "jaeger"
        }
      },
      "template": {
        "metadata": {
          "labels": {
            "app": "jaeger",
            "app.kubernetes.io/name": "jaeger",
            "app.kubernetes.io/component": "agent"
          },
          "annotations": {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "5778"
          }
        },
        "spec": {
          "containers": [
            {
              "image": std.join("", [target_registry, "docker.io/jaegertracing/jaeger-agent:", JAEGER_VERSION]),
              "name": "jaeger-agent",
              "args": [
                "--config-file=/conf/agent.yaml"
              ],
              "volumeMounts": [
                {
                  "name": "jaeger-configuration-volume",
                  "mountPath": "/conf"
                },
                {
                  "name": "jaeger-certs",
                  "mountPath": "/ca/cert",
                  "readOnly": true
                }
              ] + ( if timezone != "UTC" then [
                  {
                    "name": "timezone-config",
                    "mountPath": "/etc/localtime"
                  }
                ] else []
              ),
              "ports": [
                {
                  "containerPort": 5775,
                  "protocol": "UDP"
                },
                {
                  "containerPort": 6831,
                  "protocol": "UDP"
                },
                {
                  "containerPort": 6832,
                  "protocol": "UDP"
                },
                {
                  "containerPort": 5778,
                  "protocol": "TCP"
                }
              ],
              "readinessProbe": {
                "failureThreshold": 3,
                "httpGet": {
                  "path": "/",
                  "port": 14271,
                  "scheme": "HTTP"
                }
              }
            }
          ],
          "hostNetwork": true,
          "dnsPolicy": "ClusterFirstWithHostNet",
          "volumes": [
            {
              "name": "jaeger-certs",
              "secret":
                {
                  "defaultMode": 420,
                  "secretName": "jaeger-secret"
                }
            },
            {
              "configMap": {
                "name": "jaeger-configuration",
                "items": [
                  {
                    "key": "agent",
                    "path": "agent.yaml"
                  }
                ]
              },
              "name": "jaeger-configuration-volume"
            }
          ] + (
            if timezone != "UTC" then [
              {
                "name": "timezone-config",
                "hostPath": {
                  "path": std.join("", ["/usr/share/zoneinfo", timezone])
                }
              }
            ] else []
          )
        }
      }
    }
  }
]
