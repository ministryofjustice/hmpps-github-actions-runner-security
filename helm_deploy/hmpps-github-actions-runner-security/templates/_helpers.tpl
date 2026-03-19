{{/*
Expand the name of the chart.
*/}}
{{- define "hmpps-github-actions-runner-security.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified name.
*/}}
{{- define "hmpps-github-actions-runner-security.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hmpps-github-actions-runner-security.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "hmpps-github-actions-runner-security.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hmpps-github-actions-runner-security.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hmpps-github-actions-runner-security.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Kubernetes Secret holding credentials.
Falls back to the release name if secret.name is not set in values.
*/}}
{{- define "hmpps-github-actions-runner-security.secretName" -}}
{{- .Values.secret.name | default .Release.Name }}
{{- end }}
