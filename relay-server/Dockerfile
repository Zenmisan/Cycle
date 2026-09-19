FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /cycles-relay .

FROM scratch
COPY --from=builder /cycles-relay /cycles-relay

EXPOSE 8080
ENTRYPOINT ["/cycles-relay"]
