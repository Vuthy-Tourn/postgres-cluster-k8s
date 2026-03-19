{{/*
Expand the name of the chart.
*/}}
{{- define "postgres-cluster.name" -}}
{{- .Values.cluster.name | default "postgres-cluster" }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "postgres-cluster.namespace" -}}
{{- .Values.namespace.name | default "postgres" }}
{{- end }}

{{/*
Secret name — use existing or generated
*/}}
{{- define "postgres-cluster.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-credentials" (include "postgres-cluster.name" .) }}
{{- end }}
{{- end }}

{{/*
StorageClass name
*/}}
{{- define "postgres-cluster.storageClassName" -}}
{{- .Values.storage.storageClassName | default "postgres-storage" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgres-cluster.labels" -}}
app.kubernetes.io/name: {{ include "postgres-cluster.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
