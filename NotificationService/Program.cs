var builder = WebApplication.CreateBuilder(args);

builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "InstanaLab-NotificationService";
});

builder.Services.AddOpenApi();

var app = builder.Build();

// OpenAPI JSON disponible en: http://localhost:8082/openapi/v1.json
app.MapOpenApi();

var notifications = new List<NotificationRecord>();

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
    Console.WriteLine($"[Notification] To: {record.To} | Subject: {record.Subject}");

    return Results.Created($"/notifications/{record.Id}", record);
})
.WithName("SendNotification");

app.MapGet("/notifications", () => Results.Ok(notifications))
   .WithName("GetNotifications");

app.MapGet("/notifications/{id:int}", (int id) =>
{
    var record = notifications.FirstOrDefault(n => n.Id == id);
    return record is null ? Results.NotFound() : Results.Ok(record);
})
.WithName("GetNotificationById");

app.Run();

record NotificationRequest(string To, string Subject, string Body);
record NotificationRecord(int Id, string To, string Subject, string Body, DateTime SentAt, string Status);
