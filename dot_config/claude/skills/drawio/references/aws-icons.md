# AWS4 アイコンリファレンス

## 基本構文

### Resource Icon（推奨）
```xml
<mxCell style="sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=#ED7100;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="78" height="78" as="geometry"/>
</mxCell>
```

### Product Icon
```xml
<mxCell style="sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=#F78E04;gradientDirection=north;fillColor=#D05C17;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.productIcon;prIcon=mxgraph.aws4.lambda;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="80" height="100" as="geometry"/>
</mxCell>
```

## shape名変換規則

| 元の名前 | style値 |
|---------|---------|
| `api gateway` | `mxgraph.aws4.api_gateway` |
| `lambda function` | `mxgraph.aws4.lambda_function` |
| `s3` | `mxgraph.aws4.s3` |

**規則**: スペース → アンダースコア、小文字

## 主要サービス一覧

### Compute
| Service | Shape Name |
|---------|------------|
| EC2 | `mxgraph.aws4.ec2` |
| Lambda | `mxgraph.aws4.lambda` |
| Lambda Function | `mxgraph.aws4.lambda_function` |
| Fargate | `mxgraph.aws4.fargate` |
| ECS | `mxgraph.aws4.ecs` |
| EKS | `mxgraph.aws4.eks` |
| Elastic Beanstalk | `mxgraph.aws4.elastic_beanstalk` |
| Batch | `mxgraph.aws4.batch` |

### Storage
| Service | Shape Name |
|---------|------------|
| S3 | `mxgraph.aws4.s3` |
| S3 Bucket | `mxgraph.aws4.bucket` |
| EBS | `mxgraph.aws4.elastic_block_store` |
| EFS | `mxgraph.aws4.elastic_file_system` |
| FSx | `mxgraph.aws4.fsx` |
| Glacier | `mxgraph.aws4.glacier` |
| Storage Gateway | `mxgraph.aws4.storage_gateway` |

### Database
| Service | Shape Name |
|---------|------------|
| RDS | `mxgraph.aws4.rds` |
| Aurora | `mxgraph.aws4.aurora` |
| DynamoDB | `mxgraph.aws4.dynamodb` |
| ElastiCache | `mxgraph.aws4.elasticache` |
| Neptune | `mxgraph.aws4.neptune` |
| Redshift | `mxgraph.aws4.redshift` |
| DocumentDB | `mxgraph.aws4.documentdb_with_mongodb_compatibility` |
| MemoryDB | `mxgraph.aws4.memorydb_for_redis` |

### Networking
| Service | Shape Name |
|---------|------------|
| VPC | `mxgraph.aws4.vpc` |
| CloudFront | `mxgraph.aws4.cloudfront` |
| Route 53 | `mxgraph.aws4.route_53` |
| API Gateway | `mxgraph.aws4.api_gateway` |
| ELB | `mxgraph.aws4.elastic_load_balancing` |
| ALB | `mxgraph.aws4.application_load_balancer` |
| NLB | `mxgraph.aws4.network_load_balancer` |
| Direct Connect | `mxgraph.aws4.direct_connect` |
| Transit Gateway | `mxgraph.aws4.transit_gateway` |
| NAT Gateway | `mxgraph.aws4.nat_gateway` |
| Internet Gateway | `mxgraph.aws4.internet_gateway` |

### Integration
| Service | Shape Name |
|---------|------------|
| SQS | `mxgraph.aws4.sqs` |
| SNS | `mxgraph.aws4.sns` |
| EventBridge | `mxgraph.aws4.eventbridge` |
| Step Functions | `mxgraph.aws4.step_functions` |
| AppSync | `mxgraph.aws4.appsync` |
| MQ | `mxgraph.aws4.mq` |

### Analytics
| Service | Shape Name |
|---------|------------|
| Kinesis | `mxgraph.aws4.kinesis` |
| Kinesis Data Streams | `mxgraph.aws4.kinesis_data_streams` |
| Kinesis Data Firehose | `mxgraph.aws4.kinesis_data_firehose` |
| Athena | `mxgraph.aws4.athena` |
| Glue | `mxgraph.aws4.glue` |
| EMR | `mxgraph.aws4.emr` |
| QuickSight | `mxgraph.aws4.quicksight` |
| Data Pipeline | `mxgraph.aws4.data_pipeline` |

### Machine Learning
| Service | Shape Name |
|---------|------------|
| SageMaker | `mxgraph.aws4.sagemaker` |
| Rekognition | `mxgraph.aws4.rekognition` |
| Comprehend | `mxgraph.aws4.comprehend` |
| Lex | `mxgraph.aws4.lex` |
| Polly | `mxgraph.aws4.polly` |
| Textract | `mxgraph.aws4.textract` |
| Translate | `mxgraph.aws4.translate` |
| Bedrock | `mxgraph.aws4.bedrock` |

### Security
| Service | Shape Name |
|---------|------------|
| IAM | `mxgraph.aws4.identity_and_access_management` |
| Cognito | `mxgraph.aws4.cognito` |
| Secrets Manager | `mxgraph.aws4.secrets_manager` |
| KMS | `mxgraph.aws4.key_management_service` |
| WAF | `mxgraph.aws4.waf` |
| Shield | `mxgraph.aws4.shield` |
| GuardDuty | `mxgraph.aws4.guardduty` |
| Inspector | `mxgraph.aws4.inspector` |
| Security Hub | `mxgraph.aws4.security_hub` |

### Management
| Service | Shape Name |
|---------|------------|
| CloudWatch | `mxgraph.aws4.cloudwatch_2` |
| CloudTrail | `mxgraph.aws4.cloudtrail` |
| CloudFormation | `mxgraph.aws4.cloudformation` |
| Systems Manager | `mxgraph.aws4.systems_manager` |
| Config | `mxgraph.aws4.config` |
| Organizations | `mxgraph.aws4.organizations` |
| Control Tower | `mxgraph.aws4.control_tower` |

### Developer Tools
| Service | Shape Name |
|---------|------------|
| CodeCommit | `mxgraph.aws4.codecommit` |
| CodeBuild | `mxgraph.aws4.codebuild` |
| CodeDeploy | `mxgraph.aws4.codedeploy` |
| CodePipeline | `mxgraph.aws4.codepipeline` |
| Cloud9 | `mxgraph.aws4.cloud9` |
| X-Ray | `mxgraph.aws4.xray` |

### Containers
| Service | Shape Name |
|---------|------------|
| ECR | `mxgraph.aws4.ecr` |
| ECS Service | `mxgraph.aws4.ecs_service` |
| ECS Task | `mxgraph.aws4.ecs_task` |
| EKS Cloud | `mxgraph.aws4.eks_cloud` |

### IoT
| Service | Shape Name |
|---------|------------|
| IoT Core | `mxgraph.aws4.iot_core` |
| IoT Greengrass | `mxgraph.aws4.greengrass` |
| IoT Analytics | `mxgraph.aws4.iot_analytics` |
| IoT Events | `mxgraph.aws4.iot_events` |

## グループ（囲み枠）

```xml
<!-- AWS Cloud -->
<mxCell style="sketch=0;outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_cloud;strokeColor=#AAB7B8;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="720" height="520" as="geometry"/>
</mxCell>

<!-- VPC -->
<mxCell style="sketch=0;outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc;strokeColor=#879196;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#879196;dashed=0;" vertex="1" parent="1">
  <mxGeometry x="80" y="120" width="640" height="400" as="geometry"/>
</mxCell>

<!-- Availability Zone -->
<mxCell style="sketch=0;outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_availability_zone;strokeColor=#147EBA;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#147EBA;dashed=1;" vertex="1" parent="1">
  <mxGeometry x="120" y="160" width="240" height="320" as="geometry"/>
</mxCell>

<!-- Subnet -->
<mxCell style="sketch=0;outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_subnet;strokeColor=#879196;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#879196;dashed=0;" vertex="1" parent="1">
  <mxGeometry x="140" y="200" width="200" height="120" as="geometry"/>
</mxCell>
```

## 完全一覧の取得

1032個全てのshape名を取得:
```bash
curl -sL "https://app.diagrams.net/stencils/aws4.xml" | \
  grep -oE 'name="[^"]+"' | \
  sed 's/name="//;s/"$//' | sort -u
```

## 参考
- [draw.io AWS Diagrams](https://www.drawio.com/blog/aws-diagrams)
- [Stencils Source](https://app.diagrams.net/stencils/aws4.xml)
