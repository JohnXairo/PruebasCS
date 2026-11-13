var builder = WebApplication.CreateBuilder(args);

// -------------------------------------------------------
// Soporte Windows Service
// -------------------------------------------------------
builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "InstanaLab-NotificationService";
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

// Historial en memoria
var notifications = new List<NotificationRecord>();

// POST /notifications - registrar y "enviar" notificacion
app.MapPost("/notifications", (NotificationRequest request) =>
{
    if (string.IsNullOrWhiteSpace(request.To))
        return Results.BadRequest(new { Error = "Recipient (To) is required" });

    var record = new NotificationRecord(
        Id      : notifications.Count + 1,
        To      : request.To,
        Subject : request.Subject,
        Body    : request.Body,
        SentAt  : DateTime.UtcNow,
        Status  : "Sent"
    );

    notifications.Add(record);

    // Simulacion: en produccion aqui iria SMTP / SendGrid / etc.
    Console.WriteLine($"[Notification] To: {record.To} | Subject: {record.Subject}");

    return Results.Created($"/notifications/{record.Id}", record);
})
.WithName("SendNotification")
.WithOpenApi();

// GET /notifications - historial de notificaciones
app.MapGet("/notifications", () => Results.Ok(notifications))
   .WithName("GetNotifications")
   .WithOpenApi();

// GET /notifications/{id}
app.MapGet("/notifications/{id:int}", (int id) =>
{
    var record = notifications.FirstOrDefault(n => n.Id == id);
    return record is null ? Results.NotFound() : Results.Ok(record);
})
.WithName("GetNotificationById")
.WithOpenApi();

app.Run();

record NotificationRequest(string To, string Subject, string Body);
record NotificationRecord(int Id, string To, string Subject, string Body, DateTime SentAt, string Status);
