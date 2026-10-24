FROM golang:1.26-alpine AS build
WORKDIR /src
# Dependencies first so they stay cached until go.mod/go.sum change.
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/api .

FROM alpine:3
COPY --from=build /out/api /api
EXPOSE 8081
ENTRYPOINT ["/api"]
